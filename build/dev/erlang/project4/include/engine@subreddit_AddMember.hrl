-record(add_member, {
    user :: integer(),
    reply_to :: gleam@erlang@process:subject({ok, engine@types:subreddit()} |
        {error, engine@types:engine_error()})
}).
