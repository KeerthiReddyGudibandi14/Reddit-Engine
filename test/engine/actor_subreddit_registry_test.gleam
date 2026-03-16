import engine/subreddit_registry
import engine/user_registry
import gleeunit
import gleeunit/should
import gleam/erlang/process
import gleam/option
import gleam/set

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn create_join_leave_subreddit_test() {
  let assert Ok(user_registry_subject) = user_registry.start()
  let assert Ok(creator) =
    process.call(user_registry_subject, fn(responder) {
      user_registry.Register(name: "creator", reply_to: responder)
    }, 1000)

  let assert Ok(subreddit_registry_subject) =
    subreddit_registry.start(user_registry_subject)

  let assert Ok(created_subreddit) =
    process.call(subreddit_registry_subject, fn(responder) {
      subreddit_registry.Create(name: "gleam", creator: creator.id, reply_to: responder)
    }, 1000)

  should.equal(set.contains(created_subreddit.members, creator.id), True)

  let assert Ok(other_user) =
    process.call(user_registry_subject, fn(responder) {
      user_registry.Register(name: "second", reply_to: responder)
    }, 1000)

  let assert Ok(_) =
    process.call(subreddit_registry_subject, fn(responder) {
      subreddit_registry.Join(
        subreddit: created_subreddit.id,
        user: other_user.id,
        reply_to: responder,
      )
    }, 1000)

  let assert option.Some(joined_snapshot) =
    process.call(subreddit_registry_subject, fn(responder) {
      subreddit_registry.LookupById(
        subreddit: created_subreddit.id,
        reply_to: responder,
      )
    }, 1000)

  should.equal(set.contains(joined_snapshot.members, other_user.id), True)

  let assert Ok(_) =
    process.call(subreddit_registry_subject, fn(responder) {
      subreddit_registry.Leave(
        subreddit: created_subreddit.id,
        user: other_user.id,
        reply_to: responder,
      )
    }, 1000)

  let assert option.Some(left_snapshot) =
    process.call(subreddit_registry_subject, fn(responder) {
      subreddit_registry.LookupById(
        subreddit: created_subreddit.id,
        reply_to: responder,
      )
    }, 1000)

  should.equal(set.contains(left_snapshot.members, other_user.id), False)
}

