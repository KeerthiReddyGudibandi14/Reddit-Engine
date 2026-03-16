import engine/dm_router
import gleeunit
import gleeunit/should
import gleam/erlang/process
import gleam/list
import gleam/option

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn send_and_reply_dm_test() {
  let assert Ok(router) = dm_router.start()

  let assert Ok(message) =
    process.call(router, fn(responder) {
      dm_router.SendNew(
        from: 1,
        to: 2,
        body: "hello",
        reply_to: responder,
      )
    }, 1000)

  should.equal(message.body, "hello")

  let inbox =
    process.call(router, fn(responder) {
      dm_router.ListInbox(2, responder)
    }, 1000)

  should.equal(list.length(inbox), 1)

  let assert Ok(reply_message) =
    process.call(router, fn(responder) {
      dm_router.Reply(
        thread: message.thread,
        from: 2,
        body: "hi back",
        reply_to: responder,
      )
    }, 1000)

  should.equal(reply_message.in_reply_to, option.Some(message.id))

  let assert Ok(thread_messages) =
    process.call(router, fn(responder) {
      dm_router.ListThread(
        thread: message.thread,
        requester: 1,
        reply_to: responder,
      )
    }, 1000)

  should.equal(list.length(thread_messages), 2)
}

