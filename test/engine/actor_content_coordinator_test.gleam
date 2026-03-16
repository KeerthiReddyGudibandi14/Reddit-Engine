import engine/content_coordinator
import engine/subreddit_registry
import engine/user_registry
import engine/types
import gleeunit
import gleeunit/should
import gleam/erlang/process
import gleam/list
import gleam/option

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn post_comment_vote_flow_test() {
  let assert Ok(user_registry_subject) = user_registry.start()
  let assert Ok(author) =
    process.call(user_registry_subject, fn(responder) {
      user_registry.Register(name: "author", reply_to: responder)
    }, 1000)
  let assert Ok(voter) =
    process.call(user_registry_subject, fn(responder) {
      user_registry.Register(name: "voter", reply_to: responder)
    }, 1000)

  let assert Ok(subreddit_registry_subject) =
    subreddit_registry.start(user_registry_subject)

  let assert Ok(subreddit) =
    process.call(subreddit_registry_subject, fn(responder) {
      subreddit_registry.Create(name: "test", creator: author.id, reply_to: responder)
    }, 1000)

  let assert Ok(_) =
    process.call(subreddit_registry_subject, fn(responder) {
      subreddit_registry.Join(
        subreddit: subreddit.id,
        user: voter.id,
        reply_to: responder,
      )
    }, 1000)

  let assert Ok(coordinator_subject) =
    content_coordinator.start(user_registry_subject, subreddit_registry_subject)

  let assert Ok(post) =
    process.call(coordinator_subject, fn(responder) {
      content_coordinator.CreatePost(
        author: author.id,
        subreddit: subreddit.id,
        body: "hello world",
        reply_to: responder,
      )
    }, 1000)

  should.equal(post.author, author.id)

  let assert option.Some(fetched_post) =
    process.call(coordinator_subject, fn(responder) {
      content_coordinator.FetchPost(post.id, responder)
    }, 1000)

  should.equal(fetched_post.body, "hello world")

  let assert Ok(comment) =
    process.call(coordinator_subject, fn(responder) {
      content_coordinator.CreateComment(
        author: author.id,
        post: post.id,
        parent: option.None,
        body: "first!",
        reply_to: responder,
      )
    }, 1000)

  should.equal(comment.post, post.id)

  let comments =
    process.call(coordinator_subject, fn(responder) {
      content_coordinator.FetchComments(post.id, responder)
    }, 1000)

  should.equal(list.length(comments), 1)

  let assert Ok(updated_post) =
    process.call(coordinator_subject, fn(responder) {
      content_coordinator.VoteOnPost(
        voter: voter.id,
        post: post.id,
        vote: types.Upvote,
        reply_to: responder,
      )
    }, 1000)

  should.equal(updated_post.score, post.score + 1)
}

