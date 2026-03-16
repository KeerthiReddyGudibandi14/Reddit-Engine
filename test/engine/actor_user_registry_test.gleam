import engine/user_registry
import gleeunit
import gleeunit/should
import gleam/erlang/process
import gleam/option

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn register_and_lookup_user_test() {
  let assert Ok(subject) = user_registry.start()

  let register_result =
    process.call(subject, fn(responder) {
      user_registry.Register(name: "alice", reply_to: responder)
    }, 1000)

  let assert Ok(user) = register_result
  should.equal(user.name, "alice")

  let lookup_result =
    process.call(subject, fn(responder) {
      user_registry.LookupByName(name: "alice", reply_to: responder)
    }, 1000)

  let assert option.Some(found) = lookup_result
  should.equal(found.id, user.id)
}

pub fn adjust_karma_updates_user_test() {
  let assert Ok(subject) = user_registry.start()

  let assert Ok(user) =
    process.call(subject, fn(responder) {
      user_registry.Register(name: "karma_user", reply_to: responder)
    }, 1000)

  let assert Ok(updated) =
    process.call(subject, fn(responder) {
      user_registry.AdjustKarma(id: user.id, delta: 5, reply_to: responder)
    }, 1000)

  should.equal(updated.karma, 5)

  let assert Ok(updated_again) =
    process.call(subject, fn(responder) {
      user_registry.AdjustKarma(id: user.id, delta: -2, reply_to: responder)
    }, 1000)

  should.equal(updated_again.karma, 3)
}

