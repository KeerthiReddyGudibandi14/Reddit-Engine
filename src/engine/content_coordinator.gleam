import engine/ids
import engine/subreddit_registry
import engine/types
import engine/user_registry
import gleam/dict
import gleam/erlang.{Millisecond, system_time}
import gleam/erlang/process.{Normal, call, send, type Subject}
import gleam/int
import gleam/list
import gleam/option.{
  type Option,
  None,
  Some,
  from_result as option_from_result,
  map as option_map,
}
import gleam/otp/actor
import gleam/order
import gleam/set

/// Coordinates posts, comments, and voting across subreddits. Aligns with
/// Reddit content semantics described in https://www.reddit.com/dev/api/.
pub type Message {
  CreatePost(
    author: types.UserId,
    subreddit: types.SubredditId,
    body: String,
    reply_to: Subject(Result(types.Post, types.EngineError)),
  )
  CreateComment(
    author: types.UserId,
    post: types.PostId,
    parent: Option(types.CommentId),
    body: String,
    reply_to: Subject(Result(types.Comment, types.EngineError)),
  )
  VoteOnPost(
    voter: types.UserId,
    post: types.PostId,
    vote: types.Vote,
    reply_to: Subject(Result(types.Post, types.EngineError)),
  )
  VoteOnComment(
    voter: types.UserId,
    comment: types.CommentId,
    vote: types.Vote,
    reply_to: Subject(Result(types.Comment, types.EngineError)),
  )
  FetchPost(types.PostId, Subject(Option(types.Post)))
  FetchComments(types.PostId, Subject(List(types.Comment)))
  ListPostsBySubreddits(List(types.SubredditId), Int, Subject(List(types.Post)))
  Shutdown
}

pub fn start(
  user_registry: Subject(user_registry.Message),
  subreddit_registry: Subject(subreddit_registry.Message),
) -> Result(Subject(Message), actor.StartError) {
  start_with(1, 1, user_registry, subreddit_registry)
}

pub fn start_with(
  post_start: Int,
  comment_start: Int,
  user_registry: Subject(user_registry.Message),
  subreddit_registry: Subject(subreddit_registry.Message),
) -> Result(Subject(Message), actor.StartError) {
  actor.start(
    State(
      posts: dict.new(),
      comments: dict.new(),
      post_ids: ids.post_ids(post_start),
      comment_ids: ids.comment_ids(comment_start),
      user_registry: user_registry,
      subreddit_registry: subreddit_registry,
    ),
    handle_message,
  )
}

type PostRecord {
  PostRecord(post: types.Post, votes: dict.Dict(types.UserId, types.Vote))
}

type CommentRecord {
  CommentRecord(comment: types.Comment, votes: dict.Dict(types.UserId, types.Vote))
}

type State {
  State(
    posts: dict.Dict(types.PostId, PostRecord),
    comments: dict.Dict(types.CommentId, CommentRecord),
    post_ids: ids.IdGenerator(types.PostId),
    comment_ids: ids.IdGenerator(types.CommentId),
    user_registry: Subject(user_registry.Message),
    subreddit_registry: Subject(subreddit_registry.Message),
  )
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    CreatePost(author, subreddit, body, reply) ->
      create_post(author, subreddit, body, reply, state)
    CreateComment(author, post, parent, body, reply) ->
      create_comment(author, post, parent, body, reply, state)
    VoteOnPost(voter, post, vote, reply) ->
      vote_on_post(voter, post, vote, reply, state)
    VoteOnComment(voter, comment, vote, reply) ->
      vote_on_comment(voter, comment, vote, reply, state)
    FetchPost(post, reply) -> fetch_post(post, reply, state)
    FetchComments(post, reply) -> fetch_comments(post, reply, state)
    ListPostsBySubreddits(subreddits, limit, reply) ->
      list_posts_by_subreddits(subreddits, limit, reply, state)
    Shutdown -> actor.Stop(Normal)
  }
}

fn timestamp() -> Int {
  system_time(Millisecond)
}

fn vote_value(vote: types.Vote) -> Int {
  case vote {
    types.Upvote -> 1
    types.Downvote -> -1
  }
}

fn create_post(
  author: types.UserId,
  subreddit_id: types.SubredditId,
  body: String,
  reply: Subject(Result(types.Post, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case ensure_membership(author, subreddit_id, state) {
    Error(error) -> {
      send(reply, Error(error))
      actor.continue(state)
    }

    Ok(_) -> {
      let exists = ensure_subreddit_exists(subreddit_id, state)
      case exists {
        Error(error) -> {
          send(reply, Error(error))
          actor.continue(state)
        }

        Ok(_) -> {
          let #(post_id, next_post_ids) = ids.next(state.post_ids)
          let created_at = timestamp()
          let post =
            types.Post(
              id: post_id,
              subreddit: subreddit_id,
              author: author,
              body: body,
              created_at: created_at,
              score: 0,
            )
          let record = PostRecord(post: post, votes: dict.new())
          let posts = dict.insert(state.posts, post_id, record)

          let registry_result =
            call(
              state.subreddit_registry,
              fn(responder) {
                subreddit_registry.RecordPost(
                  subreddit: subreddit_id,
                  post: post_id,
                  reply_to: responder,
                )
              },
              5000,
            )

          case registry_result {
            Error(error) -> {
              send(reply, Error(error))
              actor.continue(state)
            }

            Ok(_updated_subreddit) -> {
              send(reply, Ok(post))
              actor.continue(State(
                posts: posts,
                comments: state.comments,
                post_ids: next_post_ids,
                comment_ids: state.comment_ids,
                user_registry: state.user_registry,
                subreddit_registry: state.subreddit_registry,
              ))
            }
          }
        }
      }
    }
  }
}

fn create_comment(
  author: types.UserId,
  post_id: types.PostId,
  parent: Option(types.CommentId),
  body: String,
  reply: Subject(Result(types.Comment, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.posts, post_id) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(PostRecord(post: post, votes: _)) -> {
      case ensure_membership(author, post.subreddit, state) {
        Error(error) -> {
          send(reply, Error(error))
          actor.continue(state)
        }

        Ok(_) -> {
          case validate_parent(parent, post_id, state) {
            Error(error) -> {
              send(reply, Error(error))
              actor.continue(state)
            }

            Ok(_) -> {
              let #(comment_id, next_comment_ids) = ids.next(state.comment_ids)
              let created_at = timestamp()
              let comment =
                types.Comment(
                  id: comment_id,
                  post: post_id,
                  parent: parent,
                  author: author,
                  body: body,
                  created_at: created_at,
                  score: 0,
                )
              let record = CommentRecord(comment: comment, votes: dict.new())
              let comments = dict.insert(state.comments, comment_id, record)
              send(reply, Ok(comment))
              actor.continue(State(
                posts: state.posts,
                comments: comments,
                post_ids: state.post_ids,
                comment_ids: next_comment_ids,
                user_registry: state.user_registry,
                subreddit_registry: state.subreddit_registry,
              ))
            }
          }
        }
      }
    }
  }
}

fn vote_on_post(
  voter: types.UserId,
  post_id: types.PostId,
  vote: types.Vote,
  reply: Subject(Result(types.Post, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.posts, post_id) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(record) -> {
      let #(votes, delta) = apply_vote(record.votes, voter, vote)
      let post = record.post
      case delta {
        0 -> {
          send(reply, Ok(post))
          actor.continue(state)
        }

        _ -> {
          let updated =
            types.Post(
              id: post.id,
              subreddit: post.subreddit,
              author: post.author,
              body: post.body,
              created_at: post.created_at,
              score: post.score + delta,
            )
          let posts = dict.insert(state.posts, post_id, PostRecord(post: updated, votes: votes))
          adjust_karma(post.author, delta, state)
          send(reply, Ok(updated))
          actor.continue(State(
            posts: posts,
            comments: state.comments,
            post_ids: state.post_ids,
            comment_ids: state.comment_ids,
            user_registry: state.user_registry,
            subreddit_registry: state.subreddit_registry,
          ))
        }
      }
    }
  }
}

fn vote_on_comment(
  voter: types.UserId,
  comment_id: types.CommentId,
  vote: types.Vote,
  reply: Subject(Result(types.Comment, types.EngineError)),
  state: State,
) -> actor.Next(Message, State) {
  case dict.get(state.comments, comment_id) {
    Error(Nil) -> {
      send(reply, Error(types.NotFound))
      actor.continue(state)
    }

    Ok(record) -> {
      let #(votes, delta) = apply_vote(record.votes, voter, vote)
      let comment = record.comment
      case delta {
        0 -> {
          send(reply, Ok(comment))
          actor.continue(state)
        }

        _ -> {
          let updated =
            types.Comment(
              id: comment.id,
              post: comment.post,
              parent: comment.parent,
              author: comment.author,
              body: comment.body,
              created_at: comment.created_at,
              score: comment.score + delta,
            )
          let comments =
            dict.insert(state.comments, comment_id, CommentRecord(comment: updated, votes: votes))
          adjust_karma(comment.author, delta, state)
          send(reply, Ok(updated))
          actor.continue(State(
            posts: state.posts,
            comments: comments,
            post_ids: state.post_ids,
            comment_ids: state.comment_ids,
            user_registry: state.user_registry,
            subreddit_registry: state.subreddit_registry,
          ))
        }
      }
    }
  }
}

fn fetch_post(
  post_id: types.PostId,
  reply: Subject(Option(types.Post)),
  state: State,
) -> actor.Next(Message, State) {
  let post =
    dict.get(state.posts, post_id)
    |> option_from_result
    |> option_map(fn(record) { record.post })
  send(reply, post)
  actor.continue(state)
}

fn fetch_comments(
  post_id: types.PostId,
  reply: Subject(List(types.Comment)),
  state: State,
) -> actor.Next(Message, State) {
  let comments =
    state.comments
    |> dict.values
    |> list.filter(fn(record) { record.comment.post == post_id })
    |> list.map(fn(record) { record.comment })
    |> list.sort(fn(a, b) {
      case int.compare(a.created_at, b.created_at) {
        order.Lt -> order.Lt
        order.Eq -> int.compare(a.id, b.id)
        order.Gt -> order.Gt
      }
    })
  send(reply, comments)
  actor.continue(state)
}

fn list_posts_by_subreddits(
  subreddit_ids: List(types.SubredditId),
  limit: Int,
  reply: Subject(List(types.Post)),
  state: State,
) -> actor.Next(Message, State) {
  let targets = set.from_list(subreddit_ids)
  let posts =
    state.posts
    |> dict.values
    |> list.map(fn(record) { record.post })
    |> list.filter(fn(post) { set.contains(targets, post.subreddit) })
    |> list.sort(fn(a, b) {
      case int.compare(a.created_at, b.created_at) {
        order.Lt -> order.Gt
        order.Eq -> int.compare(b.score, a.score)
        order.Gt -> order.Lt
      }
    })
  let limited = list.take(posts, int.max(limit, 0))
  send(reply, limited)
  actor.continue(state)
}

fn ensure_membership(
  user_id: types.UserId,
  subreddit_id: types.SubredditId,
  state: State,
) -> Result(types.UserId, types.EngineError) {
  let user_option =
    call(
      state.user_registry,
      fn(responder) {
        user_registry.LookupById(id: user_id, reply_to: responder)
      },
      5000,
    )

  case user_option {
    Some(user) -> case set.contains(user.joined_subreddits, subreddit_id) {
      True -> Ok(user_id)
      False -> Error(types.PermissionDenied)
    }

    None -> Error(types.NotFound)
  }
}

fn ensure_subreddit_exists(
  subreddit_id: types.SubredditId,
  state: State,
) -> Result(types.SubredditId, types.EngineError) {
  let subreddit_option =
    call(
      state.subreddit_registry,
      fn(responder) {
        subreddit_registry.LookupById(
          subreddit: subreddit_id,
          reply_to: responder,
        )
      },
      5000,
    )

  case subreddit_option {
    Some(_) -> Ok(subreddit_id)
    None -> Error(types.NotFound)
  }
}

fn validate_parent(
  parent: Option(types.CommentId),
  post_id: types.PostId,
  state: State,
) -> Result(Nil, types.EngineError) {
  case parent {
    None -> Ok(Nil)
    Some(comment_id) -> {
      case dict.get(state.comments, comment_id) {
        Ok(CommentRecord(comment: comment, votes: _)) -> case comment.post == post_id {
          True -> Ok(Nil)
          False -> Error(types.InvalidState)
        }
        _ -> Error(types.InvalidState)
      }
    }
  }
}

fn apply_vote(
  votes: dict.Dict(types.UserId, types.Vote),
  voter: types.UserId,
  vote: types.Vote,
) -> #(dict.Dict(types.UserId, types.Vote), Int) {
  case dict.get(votes, voter) {
    Error(Nil) -> #(dict.insert(votes, voter, vote), vote_value(vote))

    Ok(existing) -> case existing == vote {
      True -> #(dict.delete(votes, voter), -vote_value(existing))
      False ->
        #(dict.insert(votes, voter, vote), vote_value(vote) - vote_value(existing))
    }
  }
}

fn adjust_karma(author: types.UserId, delta: Int, state: State) -> Nil {
  let _ =
    call(
      state.user_registry,
      fn(responder) {
        user_registry.AdjustKarma(id: author, delta: delta, reply_to: responder)
      },
      5000,
    )
  Nil
}

