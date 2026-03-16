import gleam/option.{type Option}
import gleam/set.{type Set}

/// Core engine types aligned with Reddit concepts.
///
/// References:
/// - Reddit API overview: https://www.reddit.com/dev/api/
/// - Project brief (UF Dosp Project 4 Part I)
pub type UserId = Int

pub type SubredditId = Int

pub type PostId = Int

pub type CommentId = Int

pub type MessageId = Int

pub type ThreadId = Int

pub type Timestamp = Int

pub type Score = Int

pub type Karma = Int

/// Voting on posts and comments mirrors Reddit's boolean up/down semantics.
pub type Vote {
  Upvote
  Downvote
}

/// Domain object representing a registered account and basic profile state.
///
/// Karma aggregation follows Reddit's net-upvotes definition
/// (see https://www.reddit.com/dev/api/#section_karma for conventions).
pub type User {
  User(
    id: UserId,
    name: String,
    joined_subreddits: Set(SubredditId),
    karma: Karma,
  )
}

/// Metadata and membership for a subreddit actor.
/// Popularity and membership sizing connect to Zipf distribution sampling
/// per the project spec.
pub type Subreddit {
  Subreddit(
    id: SubredditId,
    name: String,
    members: Set(UserId),
    post_ids: List(PostId),
  )
}

/// Text-only post scoped to a subreddit.
pub type Post {
  Post(
    id: PostId,
    subreddit: SubredditId,
    author: UserId,
    body: String,
    created_at: Timestamp,
    score: Score,
  )
}

/// Hierarchical comment with optional parent pointer (None = top-level).
pub type Comment {
  Comment(
    id: CommentId,
    post: PostId,
    parent: Option(CommentId),
    author: UserId,
    body: String,
    created_at: Timestamp,
    score: Score,
  )
}

/// Message threading for direct messages: thread groups replies in-order.
pub type DirectMessage {
  DirectMessage(
    id: MessageId,
    thread: ThreadId,
    sender: UserId,
    recipient: UserId,
    body: String,
    created_at: Timestamp,
    in_reply_to: Option(MessageId),
  )
}

/// Feed ordering options used by clients and simulator policies.
pub type FeedOrder {
  Hot
  New
  Rising
}

/// Consumers of the content coordinator use these to address vote targets.
pub type VoteTarget {
  PostTarget(PostId)
  CommentTarget(CommentId)
}

/// Result values used for simple success/failure reporting by actors.
pub type EngineError {
  AlreadyExists
  NotFound
  InvalidState
  PermissionDenied
}


