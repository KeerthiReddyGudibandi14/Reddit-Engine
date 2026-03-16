import engine/content_coordinator
import engine/dm_router
import engine/feed
import engine/subreddit_registry
import engine/supervisor
import engine/types
import engine/user_registry

import gleam/bit_array
import gleam/bytes_tree
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/set

import mist

const max_request_body_bytes = 1_048_576

/// Project 4 - Part 2 HTTP server.
///
/// Run:
///   gleam run -m server
///
/// Then hit endpoints like:
///   GET  /health
///   POST /api/users/alice
///   POST /api/subreddits/technology?creator_id=1
///   POST /api/subreddits/technology/join?user_id=1
///   POST /api/subreddits/technology/leave?user_id=1
///   POST /api/subreddits/technology/posts
///   GET  /api/subreddits/technology/posts?order=hot&limit=20
///   POST /api/posts/1/comments
///   GET  /api/posts/1/comments
///   POST /api/posts/1/vote
///   POST /api/comments/5/vote
///   POST /api/messages
///   POST /api/messages/10/reply
///   GET  /api/users/1/inbox
///   GET  /api/messages/10
///
/// Body payloads are JSON as described in each handler below.
pub fn main() {
  let assert Ok(engine) = supervisor.start()

  // Build and start Mist HTTP server on port 8000.
  let assert Ok(_) =
    fn(req) { dispatch_request(req, engine) }
    |> mist.new
    |> mist.port(8000)
    |> mist.start_http

  process.sleep_forever()
}

fn dispatch_request(
  req: request.Request(mist.Connection),
  engine: supervisor.Engine,
) -> response.Response(mist.ResponseData) {
  case mist.read_body(req, max_request_body_bytes) {
    Ok(req_with_body) -> {
      let body_bits = req_with_body.body
      case bit_array.to_string(body_bits) {
        Ok(text) -> {
          let req_with_text = request.set_body(req_with_body, text)
          handle_request(req_with_text, engine)
          |> to_mist_response
        }

        Error(_) ->
          json_response(
            400,
            json.object([#("error", json.string("invalid_utf8_body"))]),
          )
          |> to_mist_response
      }
    }

    Error(mist.ExcessBody) ->
      json_response(
        413,
        json.object([#("error", json.string("body_too_large"))]),
      )
      |> to_mist_response

    Error(mist.MalformedBody) ->
      json_response(
        400,
        json.object([#("error", json.string("malformed_body"))]),
      )
      |> to_mist_response
  }
}

// ROUTER

fn handle_request(
  req: request.Request(String),
  engine: supervisor.Engine,
) -> response.Response(String) {
  let path = request.path_segments(req)

  case req.method, path {
    Get, ["health"] ->
      json_response(200, json.object([#("status", json.string("ok"))]))

    // USERS
    // POST /api/users/{username}
    Post, ["api", "users", username] -> register_user(engine, username)

    // SUBREDDITS
    // POST /api/subreddits/{name}?creator_id=ID
    Post, ["api", "subreddits", name] -> create_subreddit(engine, name, req)

    // POST /api/subreddits/{name}/join?user_id=ID
    Post, ["api", "subreddits", name, "join"] ->
      change_subscription(engine, name, req, True)

    // POST /api/subreddits/{name}/leave?user_id=ID
    Post, ["api", "subreddits", name, "leave"] ->
      change_subscription(engine, name, req, False)

    // POSTS
    // POST /api/subreddits/{name}/posts
    Post, ["api", "subreddits", name, "posts"] -> create_post(engine, name, req)

    // GET /api/subreddits/{name}/posts?order=hot|new|rising&limit=N
    Get, ["api", "subreddits", name, "posts"] ->
      list_subreddit_posts(engine, name, req)

    // COMMENTS
    // POST /api/posts/{post_id}/comments
    Post, ["api", "posts", post_id_str, "comments"] ->
      create_comment(engine, post_id_str, req)

    // GET /api/posts/{post_id}/comments
    Get, ["api", "posts", post_id_str, "comments"] ->
      list_post_comments(engine, post_id_str)

    // VOTES
    // POST /api/posts/{post_id}/vote
    Post, ["api", "posts", post_id_str, "vote"] ->
      vote_on_post(engine, post_id_str, req)

    // POST /api/comments/{comment_id}/vote
    Post, ["api", "comments", comment_id_str, "vote"] ->
      vote_on_comment(engine, comment_id_str, req)

    // DIRECT MESSAGES
    // POST /api/messages
    Post, ["api", "messages"] -> send_new_dm(engine, req)

    // POST /api/messages/{thread_id}/reply
    Post, ["api", "messages", thread_id_str, "reply"] ->
      reply_to_dm(engine, thread_id_str, req)

    // GET /api/users/{user_id}/inbox
    Get, ["api", "users", user_id_str, "inbox"] ->
      list_inbox(engine, user_id_str)

    // GET /api/messages/{thread_id}
    Get, ["api", "messages", thread_id_str] ->
      list_dm_thread(engine, thread_id_str)

    // 404
    _, _ ->
      json_response(404, json.object([#("error", json.string("not_found"))]))
  }
}

// QUERY HELPERS

fn get_query_param(
  req: request.Request(String),
  key: String,
) -> option.Option(String) {
  case request.get_query(req) {
    Error(_) -> option.None
    Ok(params) ->
      case list.find(params, fn(pair) { pair.0 == key }) {
        Ok(pair) -> option.Some(pair.1)
        Error(_) -> option.None
      }
  }
}

fn parse_int_opt(maybe: option.Option(String)) -> Result(Int, Nil) {
  case maybe {
    option.None -> Error(Nil)
    option.Some(s) -> int.parse(s)
  }
}

type PostPayload {
  PostPayload(author_id: Int, body: String)
}

type CommentPayload {
  CommentPayload(
    author_id: Int,
    body: String,
    parent_comment_id: option.Option(Int),
  )
}

type VotePayload {
  VotePayload(voter_id: Int, vote: Int)
}

type DmSendPayload {
  DmSendPayload(from_id: Int, to_id: Int, body: String)
}

type DmReplyPayload {
  DmReplyPayload(from_id: Int, body: String)
}

fn post_payload_decoder() -> decode.Decoder(PostPayload) {
  use author_id <- decode.field("author_id", decode.int)
  use body <- decode.field("body", decode.string)
  decode.success(PostPayload(author_id, body))
}

fn comment_payload_decoder() -> decode.Decoder(CommentPayload) {
  use author_id <- decode.field("author_id", decode.int)
  use body <- decode.field("body", decode.string)
  use parent <- decode.optional_field(
    "parent_comment_id",
    option.None,
    decode.optional(decode.int),
  )
  decode.success(CommentPayload(author_id, body, parent))
}

fn vote_payload_decoder() -> decode.Decoder(VotePayload) {
  use voter_id <- decode.field("voter_id", decode.int)
  use vote <- decode.field("vote", decode.int)
  decode.success(VotePayload(voter_id, vote))
}

fn dm_send_decoder() -> decode.Decoder(DmSendPayload) {
  use from_id <- decode.field("from_id", decode.int)
  use to_id <- decode.field("to_id", decode.int)
  use body <- decode.field("body", decode.string)
  decode.success(DmSendPayload(from_id, to_id, body))
}

fn dm_reply_decoder() -> decode.Decoder(DmReplyPayload) {
  use from_id <- decode.field("from_id", decode.int)
  use body <- decode.field("body", decode.string)
  decode.success(DmReplyPayload(from_id, body))
}

// USERS

fn register_user(
  engine: supervisor.Engine,
  username: String,
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  let result =
    process.try_call(
      services.user_registry,
      fn(responder) {
        user_registry.Register(name: username, reply_to: responder)
      },
      5000,
    )

  case result {
    Ok(Ok(user)) -> user_to_json_response(201, user)

    Ok(Error(err)) ->
      json_response(
        400,
        json.object([
          #("error", json.string("user_register_failed")),
          #("reason", json.string(engine_error_to_string(err))),
        ]),
      )

    Error(_) ->
      json_response(
        500,
        json.object([#("error", json.string("user_register_call_failed"))]),
      )
  }
}

fn user_to_json_response(
  status: Int,
  user: types.User,
) -> response.Response(String) {
  let types.User(id, name, joined_subs, karma) = user

  let joined =
    joined_subs
    |> set.to_list
    |> list.map(fn(sub_id) { json.int(sub_id) })

  let body =
    json.object([
      #("id", json.int(id)),
      #("name", json.string(name)),
      #("karma", json.int(karma)),
      #("joined_subreddits", json.array(joined, of: fn(value) { value })),
    ])

  json_response(status, body)
}

// SUBREDDITS

fn create_subreddit(
  engine: supervisor.Engine,
  name: String,
  req: request.Request(String),
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  let creator_id =
    parse_int_opt(get_query_param(req, "creator_id"))
    |> result.map_error(fn(_) { "invalid_creator_id" })

  case creator_id {
    Error(reason) ->
      json_response(400, json.object([#("error", json.string(reason))]))

    Ok(creator) -> {
      let result =
        process.try_call(
          services.subreddit_registry,
          fn(responder) {
            subreddit_registry.Create(
              name: name,
              creator: creator,
              reply_to: responder,
            )
          },
          5000,
        )

      case result {
        Ok(Ok(sub)) -> subreddit_to_json_response(201, sub)

        Ok(Error(err)) ->
          json_response(
            400,
            json.object([
              #("error", json.string("subreddit_create_failed")),
              #("reason", json.string(engine_error_to_string(err))),
            ]),
          )

        Error(_) ->
          json_response(
            500,
            json.object([
              #("error", json.string("subreddit_create_call_failed")),
            ]),
          )
      }
    }
  }
}

fn change_subscription(
  engine: supervisor.Engine,
  name: String,
  req: request.Request(String),
  join: Bool,
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  let user_id =
    parse_int_opt(get_query_param(req, "user_id"))
    |> result.map_error(fn(_) { "invalid_user_id" })

  case user_id {
    Error(reason) ->
      json_response(400, json.object([#("error", json.string(reason))]))

    Ok(user) -> {
      let lookup =
        process.try_call(
          services.subreddit_registry,
          fn(responder) {
            subreddit_registry.LookupByName(name: name, reply_to: responder)
          },
          5000,
        )

      case lookup {
        Ok(option.Some(sub)) -> {
          let types.Subreddit(id, _, _, _) = sub

          let result =
            process.try_call(
              services.subreddit_registry,
              fn(responder) {
                case join {
                  True ->
                    subreddit_registry.Join(
                      subreddit: id,
                      user: user,
                      reply_to: responder,
                    )

                  False ->
                    subreddit_registry.Leave(
                      subreddit: id,
                      user: user,
                      reply_to: responder,
                    )
                }
              },
              5000,
            )

          case result {
            Ok(Ok(updated)) -> subreddit_to_json_response(200, updated)

            Ok(Error(err)) ->
              json_response(
                400,
                json.object([
                  #("error", json.string("membership_change_failed")),
                  #("reason", json.string(engine_error_to_string(err))),
                ]),
              )

            Error(_) ->
              json_response(
                500,
                json.object([
                  #("error", json.string("membership_change_call_failed")),
                ]),
              )
          }
        }

        Ok(option.None) ->
          json_response(
            404,
            json.object([#("error", json.string("subreddit_not_found"))]),
          )

        Error(_) ->
          json_response(
            500,
            json.object([#("error", json.string("subreddit_lookup_failed"))]),
          )
      }
    }
  }
}

fn subreddit_to_json_response(
  status: Int,
  subreddit: types.Subreddit,
) -> response.Response(String) {
  let types.Subreddit(id, name, members, post_ids) = subreddit

  let members_json =
    members
    |> set.to_list
    |> list.map(json.int)

  let posts_json =
    post_ids
    |> list.map(json.int)

  let body =
    json.object([
      #("id", json.int(id)),
      #("name", json.string(name)),
      #("members", json.array(members_json, of: fn(value) { value })),
      #("posts", json.array(posts_json, of: fn(value) { value })),
    ])

  json_response(status, body)
}

// Posts

fn create_post(
  engine: supervisor.Engine,
  subreddit_name: String,
  req: request.Request(String),
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  case decode_body(req, post_payload_decoder()) {
    Error(_) ->
      json_response(400, json.object([#("error", json.string("invalid_json"))]))

    Ok(PostPayload(author, text)) -> {
      let lookup =
        process.try_call(
          services.subreddit_registry,
          fn(responder) {
            subreddit_registry.LookupByName(
              name: subreddit_name,
              reply_to: responder,
            )
          },
          5000,
        )

      case lookup {
        Ok(option.Some(sub)) -> {
          let types.Subreddit(sub_id, _, _, _) = sub

          let result =
            process.try_call(
              services.content_coordinator,
              fn(responder) {
                content_coordinator.CreatePost(
                  author: author,
                  subreddit: sub_id,
                  body: text,
                  reply_to: responder,
                )
              },
              5000,
            )

          case result {
            Ok(Ok(post)) -> post_to_json_response(201, post)

            Ok(Error(err)) ->
              json_response(
                400,
                json.object([
                  #("error", json.string("post_create_failed")),
                  #("reason", json.string(engine_error_to_string(err))),
                ]),
              )

            Error(_) ->
              json_response(
                500,
                json.object([
                  #("error", json.string("post_create_call_failed")),
                ]),
              )
          }
        }

        Ok(option.None) ->
          json_response(
            404,
            json.object([#("error", json.string("subreddit_not_found"))]),
          )

        Error(_) ->
          json_response(
            500,
            json.object([#("error", json.string("subreddit_lookup_failed"))]),
          )
      }
    }
  }
}

fn list_subreddit_posts(
  engine: supervisor.Engine,
  subreddit_name: String,
  req: request.Request(String),
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  let order_str = get_query_param(req, "order") |> option.unwrap("hot")

  let limit =
    parse_int_opt(get_query_param(req, "limit"))
    |> result.unwrap(50)

  // Lookup subreddit id from name
  let lookup =
    process.try_call(
      services.subreddit_registry,
      fn(responder) {
        subreddit_registry.LookupByName(
          name: subreddit_name,
          reply_to: responder,
        )
      },
      5000,
    )

  case lookup {
    Ok(option.Some(sub)) -> {
      let types.Subreddit(sub_id, _, _, _) = sub

      let fetched =
        process.try_call(
          services.content_coordinator,
          fn(responder) {
            content_coordinator.ListPostsBySubreddits(
              [sub_id],
              limit,
              responder,
            )
          },
          5000,
        )

      case fetched {
        Error(_) ->
          json_response(
            500,
            json.object([#("error", json.string("list_posts_failed"))]),
          )

        Ok(posts) -> {
          let order_by = case order_str {
            "new" -> types.New
            "rising" -> types.Rising
            _ -> types.Hot
          }

          let sorted = feed.sort_posts(posts, order_by)
          let limited = list.take(sorted, limit)
          let posts_json = limited |> list.map(post_to_json)

          json_response(200, json.array(posts_json, of: fn(value) { value }))
        }
      }
    }

    Ok(option.None) ->
      json_response(
        404,
        json.object([#("error", json.string("subreddit_not_found"))]),
      )

    Error(_) ->
      json_response(
        500,
        json.object([#("error", json.string("subreddit_lookup_failed"))]),
      )
  }
}

fn post_to_json_response(
  status: Int,
  post: types.Post,
) -> response.Response(String) {
  json_response(status, post_to_json(post))
}

fn post_to_json(post: types.Post) -> json.Json {
  let types.Post(id, subreddit, author, body, created_at, score) = post

  json.object([
    #("id", json.int(id)),
    #("subreddit_id", json.int(subreddit)),
    #("author_id", json.int(author)),
    #("body", json.string(body)),
    #("created_at", json.int(created_at)),
    #("score", json.int(score)),
  ])
}

// COMMENTS

fn create_comment(
  engine: supervisor.Engine,
  post_id_str: String,
  req: request.Request(String),
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  let post_id = int.parse(post_id_str) |> result.unwrap(0)

  case decode_body(req, comment_payload_decoder()) {
    Error(_) ->
      json_response(400, json.object([#("error", json.string("invalid_json"))]))

    Ok(CommentPayload(author_id, text, parent_id)) -> {
      let result =
        process.try_call(
          services.content_coordinator,
          fn(responder) {
            content_coordinator.CreateComment(
              author: author_id,
              post: post_id,
              parent: parent_id,
              body: text,
              reply_to: responder,
            )
          },
          5000,
        )

      case result {
        Ok(Ok(comment)) -> json_response(201, comment_to_json(comment))

        Ok(Error(err)) ->
          json_response(
            400,
            json.object([
              #("error", json.string("comment_create_failed")),
              #("reason", json.string(engine_error_to_string(err))),
            ]),
          )

        Error(_) ->
          json_response(
            500,
            json.object([
              #("error", json.string("comment_create_call_failed")),
            ]),
          )
      }
    }
  }
}

fn list_post_comments(
  engine: supervisor.Engine,
  post_id_str: String,
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  let post_id = int.parse(post_id_str) |> result.unwrap(0)

  let result =
    process.try_call(
      services.content_coordinator,
      fn(responder) { content_coordinator.FetchComments(post_id, responder) },
      5000,
    )

  case result {
    Error(_) ->
      json_response(
        500,
        json.object([#("error", json.string("fetch_comments_failed"))]),
      )

    Ok(comments) -> {
      let comments_json = comments |> list.map(comment_to_json)
      json_response(200, json.array(comments_json, of: fn(value) { value }))
    }
  }
}

fn comment_to_json(comment: types.Comment) -> json.Json {
  let types.Comment(id, post, parent, author, body, created_at, score) = comment

  let parent_json = case parent {
    option.Some(pid) -> json.int(pid)
    option.None -> json.null()
  }

  json.object([
    #("id", json.int(id)),
    #("post_id", json.int(post)),
    #("author_id", json.int(author)),
    #("body", json.string(body)),
    #("parent_comment_id", parent_json),
    #("created_at", json.int(created_at)),
    #("score", json.int(score)),
  ])
}

// VOTES

fn vote_from_int(v: Int) -> Result(types.Vote, String) {
  case v {
    1 -> Ok(types.Upvote)
    -1 -> Ok(types.Downvote)
    _ -> Error("vote_must_be_1_or_-1")
  }
}

fn vote_on_post(
  engine: supervisor.Engine,
  post_id_str: String,
  req: request.Request(String),
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  let post_id = int.parse(post_id_str) |> result.unwrap(0)

  case decode_body(req, vote_payload_decoder()) {
    Error(_) ->
      json_response(400, json.object([#("error", json.string("invalid_json"))]))

    Ok(VotePayload(voter_id, vote_int)) -> {
      case vote_from_int(vote_int) {
        Error(msg) ->
          json_response(400, json.object([#("error", json.string(msg))]))

        Ok(vote) -> {
          let result =
            process.try_call(
              services.content_coordinator,
              fn(responder) {
                content_coordinator.VoteOnPost(
                  voter: voter_id,
                  post: post_id,
                  vote: vote,
                  reply_to: responder,
                )
              },
              5000,
            )

          case result {
            Ok(Ok(post)) -> post_to_json_response(200, post)

            Ok(Error(err)) ->
              json_response(
                400,
                json.object([
                  #("error", json.string("vote_failed")),
                  #("reason", json.string(engine_error_to_string(err))),
                ]),
              )

            Error(_) ->
              json_response(
                500,
                json.object([#("error", json.string("vote_call_failed"))]),
              )
          }
        }
      }
    }
  }
}

fn vote_on_comment(
  engine: supervisor.Engine,
  comment_id_str: String,
  req: request.Request(String),
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  let comment_id = int.parse(comment_id_str) |> result.unwrap(0)

  case decode_body(req, vote_payload_decoder()) {
    Error(_) ->
      json_response(400, json.object([#("error", json.string("invalid_json"))]))

    Ok(VotePayload(voter_id, vote_int)) -> {
      case vote_from_int(vote_int) {
        Error(msg) ->
          json_response(400, json.object([#("error", json.string(msg))]))

        Ok(vote) -> {
          let result =
            process.try_call(
              services.content_coordinator,
              fn(responder) {
                content_coordinator.VoteOnComment(
                  voter: voter_id,
                  comment: comment_id,
                  vote: vote,
                  reply_to: responder,
                )
              },
              5000,
            )

          case result {
            Ok(Ok(comment)) -> json_response(200, comment_to_json(comment))

            Ok(Error(err)) ->
              json_response(
                400,
                json.object([
                  #("error", json.string("vote_failed")),
                  #("reason", json.string(engine_error_to_string(err))),
                ]),
              )

            Error(_) ->
              json_response(
                500,
                json.object([#("error", json.string("vote_call_failed"))]),
              )
          }
        }
      }
    }
  }
}

// DMs

fn send_new_dm(
  engine: supervisor.Engine,
  req: request.Request(String),
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  case decode_body(req, dm_send_decoder()) {
    Error(_) ->
      json_response(400, json.object([#("error", json.string("invalid_json"))]))

    Ok(DmSendPayload(from_id, to_id, text)) -> {
      let result =
        process.try_call(
          services.dm_router,
          fn(responder) {
            dm_router.SendNew(
              from: from_id,
              to: to_id,
              body: text,
              reply_to: responder,
            )
          },
          5000,
        )

      case result {
        Ok(Ok(message)) -> json_response(201, dm_to_json(message))

        Ok(Error(err)) ->
          json_response(
            400,
            json.object([
              #("error", json.string("dm_send_failed")),
              #("reason", json.string(engine_error_to_string(err))),
            ]),
          )

        Error(_) ->
          json_response(
            500,
            json.object([#("error", json.string("dm_send_call_failed"))]),
          )
      }
    }
  }
}

fn reply_to_dm(
  engine: supervisor.Engine,
  thread_id_str: String,
  req: request.Request(String),
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  let thread_id = int.parse(thread_id_str) |> result.unwrap(0)

  case decode_body(req, dm_reply_decoder()) {
    Error(_) ->
      json_response(400, json.object([#("error", json.string("invalid_json"))]))

    Ok(DmReplyPayload(from_id, text)) -> {
      let result =
        process.try_call(
          services.dm_router,
          fn(responder) {
            dm_router.Reply(
              thread: thread_id,
              from: from_id,
              body: text,
              reply_to: responder,
            )
          },
          5000,
        )

      case result {
        Ok(Ok(message)) -> json_response(200, dm_to_json(message))

        Ok(Error(err)) ->
          json_response(
            400,
            json.object([
              #("error", json.string("dm_reply_failed")),
              #("reason", json.string(engine_error_to_string(err))),
            ]),
          )

        Error(_) ->
          json_response(
            500,
            json.object([#("error", json.string("dm_reply_call_failed"))]),
          )
      }
    }
  }
}

fn list_inbox(
  engine: supervisor.Engine,
  user_id_str: String,
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  let user_id = int.parse(user_id_str) |> result.unwrap(0)

  let result =
    process.try_call(
      services.dm_router,
      fn(responder) { dm_router.ListInbox(user_id, responder) },
      5000,
    )

  case result {
    Error(_) ->
      json_response(
        500,
        json.object([#("error", json.string("inbox_fetch_failed"))]),
      )

    Ok(messages) -> {
      let threads_json =
        messages
        |> list.group(fn(msg) {
          let types.DirectMessage(_, thread, _, _, _, _, _) = msg
          thread
        })
        |> dict.to_list
        |> list.map(fn(group) {
          let #(thread_id, msgs) = group
          json.object([
            #("thread_id", json.int(thread_id)),
            #(
              "messages",
              json.array(list.map(msgs, dm_to_json), of: fn(value) { value }),
            ),
          ])
        })

      json_response(200, json.array(threads_json, of: fn(value) { value }))
    }
  }
}

fn list_dm_thread(
  engine: supervisor.Engine,
  thread_id_str: String,
) -> response.Response(String) {
  let supervisor.Engine(_, services) = engine

  let thread_id = int.parse(thread_id_str) |> result.unwrap(0)

  let result =
    process.try_call(
      services.dm_router,
      fn(responder) {
        dm_router.ListThread(
          thread: thread_id,
          requester: 0,
          reply_to: responder,
        )
      },
      5000,
    )

  case result {
    Error(_) ->
      json_response(
        500,
        json.object([#("error", json.string("thread_fetch_failed"))]),
      )

    Ok(Ok(messages)) -> {
      let msgs_json = messages |> list.map(dm_to_json)
      json_response(200, json.array(msgs_json, of: fn(value) { value }))
    }

    Ok(Error(err)) ->
      json_response(
        400,
        json.object([
          #("error", json.string("thread_fetch_failed")),
          #("reason", json.string(engine_error_to_string(err))),
        ]),
      )
  }
}

fn dm_to_json(dm: types.DirectMessage) -> json.Json {
  let types.DirectMessage(
    id,
    thread,
    sender,
    recipient,
    body,
    created_at,
    in_reply_to,
  ) = dm

  let in_reply_json = case in_reply_to {
    option.Some(mid) -> json.int(mid)
    option.None -> json.null()
  }

  json.object([
    #("id", json.int(id)),
    #("thread_id", json.int(thread)),
    #("sender_id", json.int(sender)),
    #("recipient_id", json.int(recipient)),
    #("body", json.string(body)),
    #("created_at", json.int(created_at)),
    #("in_reply_to", in_reply_json),
  ])
}

// JSON & ERROR HELPERS

fn decode_body(
  req: request.Request(String),
  decoder: decode.Decoder(a),
) -> Result(a, Nil) {
  json.parse(req.body, decoder)
  |> result.map_error(fn(_) { Nil })
}

fn json_response(status: Int, body: json.Json) -> response.Response(String) {
  let body_string = json.to_string(body)
  response.new(status)
  |> response.prepend_header("content-type", "application/json")
  |> response.set_body(body_string)
}

fn to_mist_response(
  resp: response.Response(String),
) -> response.Response(mist.ResponseData) {
  resp
  |> response.map(fn(body) {
    body
    |> bytes_tree.from_string
    |> mist.Bytes
  })
}

fn engine_error_to_string(err: types.EngineError) -> String {
  case err {
    types.AlreadyExists -> "already_exists"
    types.NotFound -> "not_found"
    types.InvalidState -> "invalid_state"
    types.PermissionDenied -> "permission_denied"
  }
}
