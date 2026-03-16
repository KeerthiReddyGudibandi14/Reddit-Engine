import engine/feed
import engine/types
import gleeunit
import gleeunit/should
import gleam/erlang.{Millisecond, system_time}
import gleam/list

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn sort_hot_orders_by_score_test() {
  let posts = sample_posts()
  let ordered = feed.sort_posts(posts, types.Hot)
  let expected = [1, 3, 2]
  should.equal(list.map(ordered, fn(p) { p.id }), expected)
}

pub fn sort_new_orders_by_timestamp_test() {
  let posts = sample_posts()
  let ordered = feed.sort_posts(posts, types.New)
  let expected = [2, 3, 1]
  should.equal(list.map(ordered, fn(p) { p.id }), expected)
}

pub fn sort_rising_orders_test() {
  let now = system_time(Millisecond)
  let posts = [
    types.Post(id: 1, subreddit: 1, author: 1, body: "first", created_at: now - 1000, score: 10),
    types.Post(id: 2, subreddit: 1, author: 2, body: "second", created_at: now - 200, score: 5),
    types.Post(id: 3, subreddit: 1, author: 3, body: "third", created_at: now - 400, score: 8),
  ]
  let ordered = feed.sort_posts(posts, types.Rising)
  let expected = [2, 3, 1]
  should.equal(list.map(ordered, fn(p) { p.id }), expected)
}

fn sample_posts() -> List(types.Post) {
  [
    types.Post(id: 1, subreddit: 1, author: 1, body: "first", created_at: 100, score: 10),
    types.Post(id: 2, subreddit: 1, author: 2, body: "second", created_at: 200, score: 5),
    types.Post(id: 3, subreddit: 1, author: 3, body: "third", created_at: 150, score: 8),
  ]
}

