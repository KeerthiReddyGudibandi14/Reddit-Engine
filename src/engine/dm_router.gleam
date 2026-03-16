import engine/ids
import engine/types
import gleam/dict
import gleam/erlang.{Millisecond, system_time}
import gleam/erlang/process.{Normal, send, type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/otp/actor
import gleam/set
import gleam/result

/// Direct message router coordinating point-to-point conversations.
///
/// Aligns with Reddit private messages semantics
/// (https://www.reddit.com/dev/api/#section_private_messages) for text-only
/// payloads in Part I.
pub type Message {
  SendNew(
    from: types.UserId,
    to: types.UserId,
    body: String,
    reply_to: Subject(Result(types.DirectMessage, types.EngineError)),
  )
  Reply(
    thread: types.ThreadId,
    from: types.UserId,
    body: String,
    reply_to: Subject(Result(types.DirectMessage, types.EngineError)),
  )
  ListInbox(types.UserId, Subject(List(types.DirectMessage)))
  ListThread(
    thread: types.ThreadId,
    requester: types.UserId,
    reply_to: Subject(Result(List(types.DirectMessage), types.EngineError)),
  )
  Shutdown
}

pub fn start() -> Result(Subject(Message), actor.StartError) {
  start_with(1, 1)
}

pub fn start_with(
  thread_start: Int,
  message_start: Int,
) -> Result(Subject(Message), actor.StartError) {
  actor.start(
    State(
      threads: dict.new(),
      messages: dict.new(),
      inbox: dict.new(),
      thread_ids: ids.dm_thread_ids(thread_start),
      message_ids: ids.message_ids(message_start),
    ),
    handle_message,
  )
}

type ThreadStore {
  ThreadStore(
    participants: set.Set(types.UserId),
    message_ids: List(types.MessageId),
  )
}

type State {
  State(
    threads: dict.Dict(types.ThreadId, ThreadStore),
    messages: dict.Dict(types.MessageId, types.DirectMessage),
    inbox: dict.Dict(types.UserId, List(types.MessageId)),
    thread_ids: ids.IdGenerator(types.ThreadId),
    message_ids: ids.IdGenerator(types.MessageId),
  )
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    SendNew(from, to, body, reply) -> send_new(from, to, body, reply, state)
    Reply(thread, from, body, reply) -> reply_to_thread(thread, from, body, reply, state)
    ListInbox(user, reply) -> list_inbox(user, reply, state)
    ListThread(thread, requester, reply) -> list_thread(thread, requester, reply, state)
    Shutdown -> actor.Stop(Normal)
  }
}

fn send_new(
  from: types.UserId,
  to: types.UserId,
  body: String,
  reply: Subject(Result(types.DirectMessage, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case from == to {
    True -> {
      send(reply, Error(types.InvalidState))
      actor.continue(state)
    }

    False -> {
      let #(thread_id, next_thread_ids) = ids.next(state.thread_ids)
      let #(message, state) =
        create_message(thread_id, None, from, to, body, state)
      let threads = dict.insert(
        state.threads,
        thread_id,
        ThreadStore(
          participants: set.from_list([from, to]),
          message_ids: [message.id],
        ),
      )
      send(reply, Ok(message))
      actor.continue(update_threads(state, threads, next_thread_ids))
    }
  }
}

fn reply_to_thread(
  thread: types.ThreadId,
  from: types.UserId,
  body: String,
  reply: Subject(Result(types.DirectMessage, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.threads, thread) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(ThreadStore(participants: participants, message_ids: message_ids)) ->
      case set.contains(participants, from) {
        False -> {
          send(reply, Error(types.PermissionDenied))
          actor.continue(state)
        }

        True -> {
          let in_reply_to = list.first(message_ids) |> result_to_option
          case other_participant(participants, from) {
            Error(error) -> {
              send(reply, Error(error))
              actor.continue(state)
            }

            Ok(to) -> {
              let #(message, state) =
                create_message(thread, in_reply_to, from, to, body, state)
              let threads = dict.insert(
                state.threads,
                thread,
                ThreadStore(
                  participants: participants,
                  message_ids: [message.id, ..message_ids],
                ),
              )
              send(reply, Ok(message))
              actor.continue(update_threads(state, threads, state.thread_ids))
            }
          }
        }
      }
  }
}

fn list_inbox(
  user: types.UserId,
  reply: Subject(List(types.DirectMessage)),
  state: State,
) -> actor.Next(Message, State) {
  let message_ids = dict.get(state.inbox, user) |> result_to_list([])
  let messages =
    message_ids
    |> list.filter_map(fn(id) { dict.get(state.messages, id) })
    |> list.sort(fn(a, b) { compare_desc(a.created_at, b.created_at) })
  send(reply, messages)
  actor.continue(state)
}

fn list_thread(
  thread: types.ThreadId,
  requester: types.UserId,
  reply: Subject(Result(List(types.DirectMessage), types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.threads, thread) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(ThreadStore(participants: participants, message_ids: message_ids)) ->
      case set.contains(participants, requester) {
        False -> {
          send(reply, Error(types.PermissionDenied))
          actor.continue(state)
        }

        True -> {
          let messages =
            message_ids
            |> list.filter_map(fn(id) { dict.get(state.messages, id) })
            |> list.sort(fn(a, b) { compare_asc(a.created_at, b.created_at) })
          send(reply, Ok(messages))
          actor.continue(state)
        }
      }
  }
}

fn create_message(
  thread: types.ThreadId,
  in_reply_to: Option(types.MessageId),
  from: types.UserId,
  to: types.UserId,
  body: String,
  state: State,
) -> #(types.DirectMessage, State) {
  let #(message_id, next_message_ids) = ids.next(state.message_ids)
  let timestamp = system_time(Millisecond)
  let message = types.DirectMessage(
    id: message_id,
    thread: thread,
    sender: from,
    recipient: to,
    body: body,
    created_at: timestamp,
    in_reply_to: in_reply_to,
  )
  let messages = dict.insert(state.messages, message_id, message)
  let inbox_from = update_inbox(state.inbox, from, message_id)
  let inbox = update_inbox(inbox_from, to, message_id)
  #(message, State(
    threads: state.threads,
    messages: messages,
    inbox: inbox,
    thread_ids: state.thread_ids,
    message_ids: next_message_ids,
  ))
}

fn update_threads(
  state: State,
  threads: dict.Dict(types.ThreadId, ThreadStore),
  thread_ids: ids.IdGenerator(types.ThreadId),
) -> State {
  State(
    threads: threads,
    messages: state.messages,
    inbox: state.inbox,
    thread_ids: thread_ids,
    message_ids: state.message_ids,
  )
}

fn update_inbox(
  inbox: dict.Dict(types.UserId, List(types.MessageId)),
  user: types.UserId,
  message_id: types.MessageId,
) -> dict.Dict(types.UserId, List(types.MessageId)) {
  let existing = dict.get(inbox, user) |> result_to_list([])
  dict.insert(inbox, user, [message_id, ..existing])
}

fn other_participant(
  participants: set.Set(types.UserId),
  sender: types.UserId,
) -> Result(types.UserId, types.EngineError) {
  participants
  |> set.to_list
  |> list.filter(fn(user) { user != sender })
  |> list.first
  |> result.map_error(fn(_ignored) { types.InvalidState })
}

fn compare_desc(a: Int, b: Int) -> order.Order {
  case int.compare(a, b) {
    order.Lt -> order.Gt
    order.Eq -> order.Eq
    order.Gt -> order.Lt
  }
}

fn compare_asc(a: Int, b: Int) -> order.Order {
  int.compare(a, b)
}

fn result_to_list(
  result: Result(List(types.MessageId), Nil),
  default: List(types.MessageId),
) -> List(types.MessageId) {
  case result {
    Ok(value) -> value
    Error(_) -> default
  }
}

fn result_to_option(result: Result(a, Nil)) -> Option(a) {
  case result {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

