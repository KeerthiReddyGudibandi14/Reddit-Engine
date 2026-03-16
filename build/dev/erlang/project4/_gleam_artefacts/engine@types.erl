-module(engine@types).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/engine/types.gleam").
-export_type([vote/0, user/0, subreddit/0, post/0, comment/0, direct_message/0, feed_order/0, vote_target/0, engine_error/0]).

-type vote() :: upvote | downvote.

-type user() :: {user, integer(), binary(), gleam@set:set(integer()), integer()}.

-type subreddit() :: {subreddit,
        integer(),
        binary(),
        gleam@set:set(integer()),
        list(integer())}.

-type post() :: {post,
        integer(),
        integer(),
        integer(),
        binary(),
        integer(),
        integer()}.

-type comment() :: {comment,
        integer(),
        integer(),
        gleam@option:option(integer()),
        integer(),
        binary(),
        integer(),
        integer()}.

-type direct_message() :: {direct_message,
        integer(),
        integer(),
        integer(),
        integer(),
        binary(),
        integer(),
        gleam@option:option(integer())}.

-type feed_order() :: hot | new | rising.

-type vote_target() :: {post_target, integer()} | {comment_target, integer()}.

-type engine_error() :: already_exists |
    not_found |
    invalid_state |
    permission_denied.


