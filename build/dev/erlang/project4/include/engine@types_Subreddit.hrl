-record(subreddit, {
    id :: integer(),
    name :: binary(),
    members :: gleam@set:set(integer()),
    post_ids :: list(integer())
}).
