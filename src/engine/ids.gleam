import engine/types.{
  type CommentId,
  type MessageId,
  type PostId,
  type SubredditId,
  type ThreadId,
  type UserId,
}

/// Generic monotonic integer identifier generator.
///
/// This wraps `Int` counters so actors can produce unique identifiers while
/// keeping state changes pure. Each subsystem owns its generator instance.
///
/// Reference: Reddit resources are keyed by integer IDs in multiple API
/// endpoints (https://www.reddit.com/dev/api/), so we follow the same shape
/// for Part I.
pub type IdGenerator(id) {
  IdGenerator(next: Int, wrap: fn(Int) -> id)
}

pub fn new(start_at: Int, wrap: fn(Int) -> id) -> IdGenerator(id) {
  IdGenerator(start_at, wrap)
}

pub fn next(generator: IdGenerator(id)) -> #(id, IdGenerator(id)) {
  let IdGenerator(counter, wrap) = generator
  #(wrap(counter), IdGenerator(counter + 1, wrap))
}

pub fn user_ids(start_at: Int) -> IdGenerator(UserId) {
  new(start_at, fn(x) { x })
}

pub fn subreddit_ids(start_at: Int) -> IdGenerator(SubredditId) {
  new(start_at, fn(x) { x })
}

pub fn post_ids(start_at: Int) -> IdGenerator(PostId) {
  new(start_at, fn(x) { x })
}

pub fn comment_ids(start_at: Int) -> IdGenerator(CommentId) {
  new(start_at, fn(x) { x })
}

pub fn dm_thread_ids(start_at: Int) -> IdGenerator(ThreadId) {
  new(start_at, fn(x) { x })
}

pub fn message_ids(start_at: Int) -> IdGenerator(MessageId) {
  new(start_at, fn(x) { x })
}

