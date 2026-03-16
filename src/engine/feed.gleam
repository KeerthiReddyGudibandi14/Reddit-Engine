import engine/content_coordinator
import engine/types
import gleam/erlang.{Millisecond, system_time}
import gleam/erlang/process.{try_call, type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/order

/// Feed utilities for sorting Reddit-style listings (hot/new/rising).
pub fn sort_posts(
  posts: List(types.Post),
  order_by: types.FeedOrder,
) -> List(types.Post) {
  case order_by {
    types.Hot -> sort_hot(posts)
    types.New -> sort_new(posts)
    types.Rising -> sort_rising(posts)
  }
}

pub fn truncate(posts: List(types.Post), up_to count: Int) -> List(types.Post) {
  list.take(posts, count)
}

pub fn fetch_feed(
  coordinator: Subject(content_coordinator.Message),
  subreddits: List(types.SubredditId),
  order_by: types.FeedOrder,
  limit: Int,
) -> Result(List(types.Post), Nil) {
  let response =
    try_call(
      coordinator,
      fn(responder) {
        content_coordinator.ListPostsBySubreddits(
          subreddits,
          limit * 3,
          responder,
        )
      },
      5000,
    )

  case response {
    Error(_) -> Error(Nil)
    Ok(posts) -> Ok(posts |> sort_posts(order_by) |> truncate(limit))
  }
}

fn sort_hot(posts: List(types.Post)) -> List(types.Post) {
  list.sort(posts, fn(post_a, post_b) {
    case compare_int_desc(post_a.score, post_b.score) {
      order.Eq -> compare_int_desc(post_a.created_at, post_b.created_at)
      other -> other
    }
  })
}

fn sort_new(posts: List(types.Post)) -> List(types.Post) {
  list.sort(posts, fn(post_a, post_b) {
    case compare_int_desc(post_a.created_at, post_b.created_at) {
      order.Eq -> compare_int_desc(post_a.id, post_b.id)
      other -> other
    }
  })
}

fn sort_rising(posts: List(types.Post)) -> List(types.Post) {
  let now = system_time(Millisecond)
  list.sort(posts, fn(post_a, post_b) {
    let score_a = rising_metric(post_a, now)
    let score_b = rising_metric(post_b, now)
    case compare_float_desc(score_a, score_b) {
      order.Eq -> compare_int_desc(post_a.score, post_b.score)
      other -> other
    }
  })
}

fn rising_metric(post: types.Post, now: Int) -> Float {
  let age = int.max(now - post.created_at, 1)
  int.to_float(post.score) /. int.to_float(age)
}

fn compare_int_desc(a: Int, b: Int) -> order.Order {
  case int.compare(a, b) {
    order.Lt -> order.Gt
    order.Eq -> order.Eq
    order.Gt -> order.Lt
  }
}

fn compare_float_desc(a: Float, b: Float) -> order.Order {
  case float.compare(a, b) {
    order.Lt -> order.Gt
    order.Eq -> order.Eq
    order.Gt -> order.Lt
  }
}

