import engine/types as types
import gleam/erlang/process.{Normal, send, type Subject}
import gleam/list
import gleam/otp/actor
import gleam/set

/// Subreddit actor tracks membership and the rolling post index for a single
/// community. This aligns with Reddit's community ownership semantics:
/// https://www.reddit.com/dev/api/#section_subreddits
pub type Message {
  Snapshot(Subject(types.Subreddit))
  AddMember(
    user: types.UserId,
    reply_to: Subject(Result(types.Subreddit, types.EngineError)),
  )
  RemoveMember(
    user: types.UserId,
    reply_to: Subject(Result(types.Subreddit, types.EngineError)),
  )
  RecordPost(post: types.PostId, reply_to: Subject(types.Subreddit))
  RemovePost(post: types.PostId, reply_to: Subject(types.Subreddit))
  ListPosts(Subject(List(types.PostId)))
  Shutdown
}

pub fn start(initial: types.Subreddit) -> Result(Subject(Message), actor.StartError) {
  actor.start(State(info: initial), handle_message)
}

type State {
  State(info: types.Subreddit)
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    Snapshot(reply) -> {
      send(reply, state.info)
      actor.continue(state)
    }

    AddMember(user, reply) -> add_member(user, reply, state)
    RemoveMember(user, reply) -> remove_member(user, reply, state)
    RecordPost(post, reply) -> record_post(post, reply, state)
    RemovePost(post, reply) -> remove_post(post, reply, state)
    ListPosts(reply) -> {
      send(reply, state.info.post_ids)
      actor.continue(state)
    }
    Shutdown -> actor.Stop(Normal)
  }
}

fn add_member(
  user: types.UserId,
  reply: Subject(Result(types.Subreddit, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  let info = state.info

  case set.contains(info.members, user) {
    True -> {
      send(reply, Ok(info))
      actor.continue(state)
    }

    False -> {
      let members = set.insert(info.members, user)
      let updated =
        types.Subreddit(
          id: info.id,
          name: info.name,
          members: members,
          post_ids: info.post_ids,
        )
      send(reply, Ok(updated))
      actor.continue(State(info: updated))
    }
  }
}

fn remove_member(
  user: types.UserId,
  reply: Subject(Result(types.Subreddit, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  let info = state.info

  case set.contains(info.members, user) {
    False -> {
      send(reply, Error(types.InvalidState))
      actor.continue(state)
    }

    True -> {
      let members = set.delete(info.members, user)
      let updated =
        types.Subreddit(
          id: info.id,
          name: info.name,
          members: members,
          post_ids: info.post_ids,
        )
      send(reply, Ok(updated))
      actor.continue(State(info: updated))
    }
  }
}

fn record_post(
  post: types.PostId,
  reply: Subject(types.Subreddit),
  state: State,
) -> actor.Next(Message, State) {
  let info = state.info
  let already_indexed = list.contains(info.post_ids, post)
  let posts = case already_indexed {
    True -> info.post_ids
    False -> [post, ..info.post_ids]
  }
  let updated =
    types.Subreddit(
      id: info.id,
      name: info.name,
      members: info.members,
      post_ids: posts,
    )
  send(reply, updated)
  actor.continue(State(info: updated))
}

fn remove_post(
  target: types.PostId,
  reply: Subject(types.Subreddit),
  state: State,
) -> actor.Next(Message, State) {
  let pruned = list.filter(state.info.post_ids, fn(post) { post != target })
  let updated =
    types.Subreddit(
      id: state.info.id,
      name: state.info.name,
      members: state.info.members,
      post_ids: pruned,
    )
  send(reply, updated)
  actor.continue(State(info: updated))
}

