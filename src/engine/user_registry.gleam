import engine/ids
import engine/types
import gleam/dict
import gleam/erlang/process.{type Subject, Normal, send}
import gleam/option
import gleam/otp/actor
import gleam/set

/// User registry actor manages registration, lookup, and karma tracking.
///
/// Concurrency follows Gleam OTP guidelines:
/// https://hexdocs.pm/gleam_otp/gleam/otp/actor.html
pub type Message {
  Register(
    name: String,
    reply_to: Subject(Result(types.User, types.EngineError)),
  )
  LookupById(id: types.UserId, reply_to: Subject(option.Option(types.User)))
  LookupByName(name: String, reply_to: Subject(option.Option(types.User)))
  AdjustKarma(
    id: types.UserId,
    delta: Int,
    reply_to: Subject(Result(types.User, types.EngineError)),
  )
  AddMembership(
    user: types.UserId,
    subreddit: types.SubredditId,
    reply_to: Subject(Result(types.User, types.EngineError)),
  )
  RemoveMembership(
    user: types.UserId,
    subreddit: types.SubredditId,
    reply_to: Subject(Result(types.User, types.EngineError)),
  )
  Shutdown
}

pub fn start() -> Result(Subject(Message), actor.StartError) {
  start_with(1)
}

pub fn start_with(start_id: Int) -> Result(Subject(Message), actor.StartError) {
  actor.start(new_state(start_id), handle_message)
}

type State {
  State(
    users: dict.Dict(types.UserId, types.User),
    names: dict.Dict(String, types.UserId),
    ids: ids.IdGenerator(types.UserId),
  )
}

fn new_state(start_id: Int) -> State {
  State(users: dict.new(), names: dict.new(), ids: ids.user_ids(start_id))
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    Register(name, reply) -> register(name, reply, state)
    LookupById(id, reply) -> lookup_by_id(id, reply, state)
    LookupByName(name, reply) -> lookup_by_name(name, reply, state)
    AdjustKarma(id, delta, reply) -> adjust_karma(id, delta, reply, state)
    AddMembership(user, subreddit, reply) ->
      add_membership(user, subreddit, reply, state)
    RemoveMembership(user, subreddit, reply) ->
      remove_membership(user, subreddit, reply, state)
    Shutdown -> actor.Stop(Normal)
  }
}

fn register(
  name: String,
  reply: Subject(Result(types.User, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.names, name) {
    Ok(_) -> {
      send(reply, Error(types.AlreadyExists))
      actor.continue(state)
    }

    Error(Nil) -> {
      let #(user_id, next_ids) = ids.next(state.ids)
      let user =
        types.User(
          id: user_id,
          name: name,
          joined_subreddits: set.new(),
          karma: 0,
        )
      let users = dict.insert(state.users, user_id, user)
      let names = dict.insert(state.names, name, user_id)
      send(reply, Ok(user))
      actor.continue(State(users: users, names: names, ids: next_ids))
    }
  }
}

fn add_membership(
  user: types.UserId,
  subreddit: types.SubredditId,
  reply: Subject(Result(types.User, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.users, user) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(profile) -> {
      let already_joined = set.contains(profile.joined_subreddits, subreddit)
      let joined = case already_joined {
        True -> profile.joined_subreddits
        False -> set.insert(profile.joined_subreddits, subreddit)
      }
      let updated =
        types.User(
          id: profile.id,
          name: profile.name,
          joined_subreddits: joined,
          karma: profile.karma,
        )
      let users = dict.insert(state.users, user, updated)
      send(reply, Ok(updated))
      actor.continue(State(users: users, names: state.names, ids: state.ids))
    }
  }
}

fn remove_membership(
  user: types.UserId,
  subreddit: types.SubredditId,
  reply: Subject(Result(types.User, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.users, user) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(profile) -> {
      case set.contains(profile.joined_subreddits, subreddit) {
        False -> {
          send(reply, Error(types.InvalidState))
          actor.continue(state)
        }

        True -> {
          let joined = set.delete(profile.joined_subreddits, subreddit)
          let updated =
            types.User(
              id: profile.id,
              name: profile.name,
              joined_subreddits: joined,
              karma: profile.karma,
            )
          let users = dict.insert(state.users, user, updated)
          send(reply, Ok(updated))
          actor.continue(State(users: users, names: state.names, ids: state.ids))
        }
      }
    }
  }
}

fn lookup_by_id(
  id: types.UserId,
  reply: Subject(option.Option(types.User)),
  state: State,
) -> actor.Next(Message, State) {
  send(reply, option.from_result(dict.get(state.users, id)))
  actor.continue(state)
}

fn lookup_by_name(
  name: String,
  reply: Subject(option.Option(types.User)),
  state: State,
) -> actor.Next(Message, State) {
  let user =
    option.from_result(dict.get(state.names, name))
    |> option.then(fn(user_id) {
      option.from_result(dict.get(state.users, user_id))
    })
  send(reply, user)
  actor.continue(state)
}

fn adjust_karma(
  id: types.UserId,
  delta: Int,
  reply: Subject(Result(types.User, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.users, id) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(user) -> {
      let updated =
        types.User(
          id: user.id,
          name: user.name,
          joined_subreddits: user.joined_subreddits,
          karma: user.karma + delta,
        )
      let users = dict.insert(state.users, id, updated)
      send(reply, Ok(updated))
      actor.continue(State(users: users, names: state.names, ids: state.ids))
    }
  }
}
