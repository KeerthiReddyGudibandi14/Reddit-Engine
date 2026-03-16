import engine/content_coordinator
import engine/subreddit_registry
import engine/supervisor as engine
import engine/types
import engine/user_registry
import gleam/dict
import gleam/erlang/process.{Normal, call, send, type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/string
import sim/coordinator

/// Simulator client actor modelling a single Reddit-like user session.
pub type Message {
  Begin
  Tick
  Shutdown
}

pub type ClientConfig {
  ClientConfig(
    username_prefix: String,
    home_subreddits: List(String),
    post_body: String,
  )
}

pub fn start(
  id: Int,
  label: String,
  engine_services: engine.Services,
  coordinator_subject: Subject(coordinator.Message),
  config: ClientConfig,
) -> Result(Subject(Message), actor.StartError) {
  actor.start(
    State(
      id: id,
      label: label,
      engine: engine_services,
      coordinator: coordinator_subject,
      config: config,
      user: None,
      subscriptions: dict.new(),
      posts: [],
      tick: 0,
    ),
    handle_message,
  )
}

type State {
  State(
    id: Int,
    label: String,
    engine: engine.Services,
    coordinator: Subject(coordinator.Message),
    config: ClientConfig,
    user: Option(types.User),
    subscriptions: dict.Dict(String, types.SubredditId),
    posts: List(types.PostId),
    tick: Int,
  )
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    Begin -> actor.continue(state |> ensure_user |> ensure_home_subreddits)
    Tick -> actor.continue(state |> ensure_user |> ensure_home_subreddits |> perform_action |> increment_tick)
    Shutdown -> actor.Stop(Normal)
  }
}

fn ensure_user(state: State) -> State {
  case state.user {
    Some(_) -> state
    None -> {
      let username =
        string.concat([state.config.username_prefix, "-", int.to_string(state.id)])
      let result =
        call(
          state.engine.user_registry,
          fn(responder) {
            user_registry.Register(name: username, reply_to: responder)
          },
          5000,
        )

      case result {
        Ok(user) -> {
          record_operation(state, "user_register")
          set_user(state, Some(user))
        }

        Error(_engine_error) -> state
      }
    }
  }
}

fn ensure_home_subreddits(state: State) -> State {
  list.fold(
    state.config.home_subreddits,
    state,
    fn(state_acc, name) { ensure_subscription(name, state_acc) },
  )
}

fn ensure_subscription(name: String, state: State) -> State {
  case state.user {
    None -> state
    Some(user) -> {
      case dict.get(state.subscriptions, name) {
        Ok(_subreddit_id) -> state
        Error(Nil) -> {
          case resolve_subreddit(name, user, state) {
            None -> state
            Some(subreddit_id) -> {
              let updated_subscriptions =
                dict.insert(state.subscriptions, name, subreddit_id)
              let state_with_subscription =
                set_subscriptions(state, updated_subscriptions)
              let _ =
                call(
                  state.engine.subreddit_registry,
                  fn(responder) {
                    subreddit_registry.Join(
                      subreddit: subreddit_id,
                      user: user.id,
                      reply_to: responder,
                    )
                  },
                  5000,
                )
              let refreshed = refresh_user(state_with_subscription, user.id)
              record_operation(refreshed, "subreddit_join")
              refreshed
            }
          }
        }
      }
    }
  }
}

fn resolve_subreddit(
  name: String,
  user: types.User,
  state: State,
) -> Option(types.SubredditId) {
  let lookup =
    call(
      state.engine.subreddit_registry,
      fn(responder) {
        subreddit_registry.LookupByName(name: name, reply_to: responder)
      },
      5000,
    )

  let maybe_existing =
    case lookup {
      Some(subreddit) -> Some(subreddit.id)
      None -> None
    }

  case maybe_existing {
    Some(subreddit_id) -> Some(subreddit_id)
    None -> {
      let created =
        call(
          state.engine.subreddit_registry,
          fn(responder) {
            subreddit_registry.Create(
              name: name,
              creator: user.id,
              reply_to: responder,
            )
          },
          5000,
        )

      case created {
        Ok(subreddit) -> Some(subreddit.id)
        Error(_engine_error) -> None
      }
    }
  }
}

fn refresh_user(state: State, user_id: types.UserId) -> State {
  let lookup =
    call(
      state.engine.user_registry,
      fn(responder) {
        user_registry.LookupById(id: user_id, reply_to: responder)
      },
      5000,
    )

  case lookup {
    Some(user) -> set_user(state, Some(user))
    None -> state
  }
}

fn perform_action(state: State) -> State {
  case state.user {
    None -> state
    Some(_) ->
      case list.length(dict.to_list(state.subscriptions)) {
        0 -> state
        _ ->
          case safe_mod(state.tick, 3) {
            0 -> attempt_post(state)
            1 -> attempt_comment(state)
            _ -> attempt_vote(state)
          }
      }
  }
}

fn attempt_post(state: State) -> State {
  case state.user {
    None -> state
    Some(user) ->
      case pick_subreddit(state, state.tick) {
        None -> state
        Some(subreddit_id) -> {
          let body =
            string.concat([
              state.config.post_body,
              " #",
              int.to_string(state.tick),
              " by ",
              state.label,
            ])

          let result =
            call(
              state.engine.content_coordinator,
              fn(responder) {
                content_coordinator.CreatePost(
                  author: user.id,
                  subreddit: subreddit_id,
                  body: body,
                  reply_to: responder,
                )
              },
              5000,
            )

          case result {
            Ok(post) -> {
              record_operation(state, "post_create")
              set_posts(state, [post.id, ..state.posts])
            }

            Error(_engine_error) -> state
          }
        }
      }
  }
}

fn attempt_comment(state: State) -> State {
  case state.user {
    None -> state
    Some(user) ->
      case state.posts {
        [] -> state
        [post_id, .._] -> {
          let result =
            call(
              state.engine.content_coordinator,
              fn(responder) {
                content_coordinator.CreateComment(
                  author: user.id,
                  post: post_id,
                  parent: None,
                  body: string.concat([
                    "Re: post #",
                    int.to_string(post_id),
                    " from ",
                    state.label,
                  ]),
                  reply_to: responder,
                )
              },
              5000,
            )

          case result {
            Ok(_comment) -> {
              record_operation(state, "comment_create")
              state
            }

            Error(_engine_error) -> state
          }
        }
      }
  }
}

fn attempt_vote(state: State) -> State {
  case state.user {
    None -> state
    Some(user) ->
      case state.posts {
        [] -> state
        [post_id, .._] -> {
          let result =
            call(
              state.engine.content_coordinator,
              fn(responder) {
                content_coordinator.VoteOnPost(
                  voter: user.id,
                  post: post_id,
                  vote: types.Upvote,
                  reply_to: responder,
                )
              },
              5000,
            )

          case result {
            Ok(_post) -> {
              record_operation(state, "vote_up")
              state
            }

            Error(_engine_error) -> state
          }
        }
      }
  }
}

fn pick_subreddit(state: State, seed: Int) -> Option(types.SubredditId) {
  let entries = dict.to_list(state.subscriptions)
  case entries {
    [] -> None
    _ -> {
      let index = safe_mod(seed, list.length(entries))
      case list.drop(entries, index) {
        [#(_name, subreddit_id), .._] -> Some(subreddit_id)
        _ -> None
      }
    }
  }
}

fn increment_tick(state: State) -> State {
  set_tick(state, state.tick + 1)
}

fn safe_mod(value: Int, divisor: Int) -> Int {
  let positive_divisor =
    case divisor {
      _ if divisor < 0 -> -divisor
      _ -> divisor
    }

  case positive_divisor {
    0 -> 0
    _ if value < 0 -> safe_mod(value + positive_divisor, positive_divisor)
    _ if value >= positive_divisor -> safe_mod(value - positive_divisor, positive_divisor)
    _ -> value
  }
}

fn record_operation(state: State, kind: String) {
  send(
    state.coordinator,
    coordinator.RecordSample(source: state.label, sample: coordinator.OperationRecorded(kind: kind)),
  )
}

fn set_user(state: State, user: Option(types.User)) -> State {
  State(
    id: state.id,
    label: state.label,
    engine: state.engine,
    coordinator: state.coordinator,
    config: state.config,
    user: user,
    subscriptions: state.subscriptions,
    posts: state.posts,
    tick: state.tick,
  )
}

fn set_subscriptions(
  state: State,
  subscriptions: dict.Dict(String, types.SubredditId),
) -> State {
  State(
    id: state.id,
    label: state.label,
    engine: state.engine,
    coordinator: state.coordinator,
    config: state.config,
    user: state.user,
    subscriptions: subscriptions,
    posts: state.posts,
    tick: state.tick,
  )
}

fn set_posts(state: State, posts: List(types.PostId)) -> State {
  State(
    id: state.id,
    label: state.label,
    engine: state.engine,
    coordinator: state.coordinator,
    config: state.config,
    user: state.user,
    subscriptions: state.subscriptions,
    posts: posts,
    tick: state.tick,
  )
}

fn set_tick(state: State, tick: Int) -> State {
  State(
    id: state.id,
    label: state.label,
    engine: state.engine,
    coordinator: state.coordinator,
    config: state.config,
    user: state.user,
    subscriptions: state.subscriptions,
    posts: state.posts,
    tick: tick,
  )
}

