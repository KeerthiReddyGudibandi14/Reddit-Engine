-record(add_membership, {
    user :: integer(),
    subreddit :: integer(),
    reply_to :: gleam@erlang@process:subject({ok, engine@types:user()} |
        {error, engine@types:engine_error()})
}).
