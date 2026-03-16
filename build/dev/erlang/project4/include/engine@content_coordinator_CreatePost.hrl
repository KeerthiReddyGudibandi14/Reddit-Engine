-record(create_post, {
    author :: integer(),
    subreddit :: integer(),
    body :: binary(),
    reply_to :: gleam@erlang@process:subject({ok, engine@types:post()} |
        {error, engine@types:engine_error()})
}).
