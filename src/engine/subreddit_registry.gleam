import engine/ids
import engine/subreddit
import engine/types
import engine/user_registry
import gleam/dict
import gleam/erlang/process.{type Subject, Normal, call, send}
import gleam/option
import gleam/otp/actor
import gleam/set

/// Subreddit registry manages creation, membership, and lookup for subreddit
/// actors. Mirrors the Reddit concept catalogue:
/// https://www.reddit.com/dev/api/#section_subreddits
pub type Message {
  Create(
    name: String,
    creator: types.UserId,
    reply_to: Subject(Result(types.Subreddit, types.EngineError)),
  )
  Join(
    subreddit: types.SubredditId,
    user: types.UserId,
    reply_to: Subject(Result(types.Subreddit, types.EngineError)),
  )
  Leave(
    subreddit: types.SubredditId,
    user: types.UserId,
    reply_to: Subject(Result(types.Subreddit, types.EngineError)),
  )
  LookupById(
    subreddit: types.SubredditId,
    reply_to: Subject(option.Option(types.Subreddit)),
  )
  LookupByName(name: String, reply_to: Subject(option.Option(types.Subreddit)))
  RecordPost(
    subreddit: types.SubredditId,
    post: types.PostId,
    reply_to: Subject(Result(types.Subreddit, types.EngineError)),
  )
  RemovePost(
    subreddit: types.SubredditId,
    post: types.PostId,
    reply_to: Subject(Result(types.Subreddit, types.EngineError)),
  )
  Shutdown
}

pub fn start(
  user_registry: Subject(user_registry.Message),
) -> Result(Subject(Message), actor.StartError) {
  start_with(1, user_registry)
}

pub fn start_with(
  start_id: Int,
  user_registry: Subject(user_registry.Message),
) -> Result(Subject(Message), actor.StartError) {
  actor.start(new_state(start_id, user_registry), handle_message)
}

type State {
  State(
    subreddits: dict.Dict(types.SubredditId, Entry),
    names: dict.Dict(String, types.SubredditId),
    ids: ids.IdGenerator(types.SubredditId),
    user_registry: Subject(user_registry.Message),
  )
}

type Entry {
  Entry(subject: Subject(subreddit.Message))
}

fn new_state(
  start_id: Int,
  user_registry: Subject(user_registry.Message),
) -> State {
  State(
    subreddits: dict.new(),
    names: dict.new(),
    ids: ids.subreddit_ids(start_id),
    user_registry: user_registry,
  )
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    Create(name, creator, reply) ->
      create_subreddit(name, creator, reply, state)
    Join(subreddit, user, reply) ->
      join_subreddit(subreddit, user, reply, state)
    Leave(subreddit, user, reply) ->
      leave_subreddit(subreddit, user, reply, state)
    LookupById(subreddit, reply) -> lookup_by_id(subreddit, reply, state)
    LookupByName(name, reply) -> lookup_by_name(name, reply, state)
    RecordPost(subreddit, post, reply) ->
      record_post(subreddit, post, reply, state)
    RemovePost(subreddit, post, reply) ->
      remove_post(subreddit, post, reply, state)
    Shutdown -> actor.Stop(Normal)
  }
}

fn create_subreddit(
  name: String,
  creator: types.UserId,
  reply: Subject(Result(types.Subreddit, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.names, name) {
    Ok(_) -> {
      send(reply, Error(types.AlreadyExists))
      actor.continue(state)
    }

    Error(Nil) -> {
      let #(subreddit_id, next_ids) = ids.next(state.ids)
      let members = set.insert(set.new(), creator)
      let snapshot =
        types.Subreddit(
          id: subreddit_id,
          name: name,
          members: members,
          post_ids: [],
        )

      case subreddit.start(snapshot) {
        Error(_err) -> {
          send(reply, Error(types.InvalidState))
          actor.continue(state)
        }

        Ok(subject) -> {
          // Update creator membership in user registry (idempotent)
          send(reply, Ok(snapshot))
          let _ =
            call(
              state.user_registry,
              fn(responder) {
                user_registry.AddMembership(
                  user: creator,
                  subreddit: subreddit_id,
                  reply_to: responder,
                )
              },
              5000,
            )
          let entry = Entry(subject: subject)
          let subreddits = dict.insert(state.subreddits, subreddit_id, entry)
          let names = dict.insert(state.names, name, subreddit_id)
          actor.continue(State(
            subreddits: subreddits,
            names: names,
            ids: next_ids,
            user_registry: state.user_registry,
          ))
        }
      }
    }
  }
}

fn join_subreddit(
  subreddit_id: types.SubredditId,
  user: types.UserId,
  reply: Subject(Result(types.Subreddit, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.subreddits, subreddit_id) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(entry) -> {
      let result =
        call(
          entry.subject,
          fn(responder) { subreddit.AddMember(user: user, reply_to: responder) },
          5000,
        )

      case result {
        Error(engine_error) -> {
          send(reply, Error(engine_error))
          actor.continue(state)
        }

        Ok(updated) -> {
          let _ =
            call(
              state.user_registry,
              fn(responder) {
                user_registry.AddMembership(
                  user: user,
                  subreddit: subreddit_id,
                  reply_to: responder,
                )
              },
              5000,
            )
          send(reply, Ok(updated))
          actor.continue(state)
        }
      }
    }
  }
}

fn leave_subreddit(
  subreddit_id: types.SubredditId,
  user: types.UserId,
  reply: Subject(Result(types.Subreddit, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.subreddits, subreddit_id) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(entry) -> {
      let result =
        call(
          entry.subject,
          fn(responder) {
            subreddit.RemoveMember(user: user, reply_to: responder)
          },
          5000,
        )

      case result {
        Error(engine_error) -> {
          send(reply, Error(engine_error))
          actor.continue(state)
        }

        Ok(updated) -> {
          let _ =
            call(
              state.user_registry,
              fn(responder) {
                user_registry.RemoveMembership(
                  user: user,
                  subreddit: subreddit_id,
                  reply_to: responder,
                )
              },
              5000,
            )
          send(reply, Ok(updated))
          actor.continue(state)
        }
      }
    }
  }
}

fn lookup_by_id(
  subreddit_id: types.SubredditId,
  reply: Subject(option.Option(types.Subreddit)),
  state: State,
) -> actor.Next(Message, State) {
  let snapshot =
    dict.get(state.subreddits, subreddit_id)
    |> option.from_result
    |> option.map(fn(entry) { fetch_snapshot(entry) })
  send(reply, snapshot)
  actor.continue(state)
}

fn lookup_by_name(
  name: String,
  reply: Subject(option.Option(types.Subreddit)),
  state: State,
) -> actor.Next(Message, State) {
  let subreddit =
    option.from_result(dict.get(state.names, name))
    |> option.then(fn(id) { option.from_result(dict.get(state.subreddits, id)) })
    |> option.map(fn(entry) { fetch_snapshot(entry) })
  send(reply, subreddit)
  actor.continue(state)
}

fn fetch_snapshot(entry: Entry) -> types.Subreddit {
  call(entry.subject, subreddit.Snapshot, 5000)
}

fn record_post(
  subreddit_id: types.SubredditId,
  post: types.PostId,
  reply: Subject(Result(types.Subreddit, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.subreddits, subreddit_id) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(entry) -> {
      let updated =
        call(
          entry.subject,
          fn(responder) {
            subreddit.RecordPost(post: post, reply_to: responder)
          },
          5000,
        )
      send(reply, Ok(updated))
      actor.continue(state)
    }
  }
}

fn remove_post(
  subreddit_id: types.SubredditId,
  post: types.PostId,
  reply: Subject(Result(types.Subreddit, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.subreddits, subreddit_id) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(entry) -> {
      let updated =
        call(
          entry.subject,
          fn(responder) {
            subreddit.RemovePost(post: post, reply_to: responder)
          },
          5000,
        )
      send(reply, Ok(updated))
      actor.continue(state)
    }
  }
}
