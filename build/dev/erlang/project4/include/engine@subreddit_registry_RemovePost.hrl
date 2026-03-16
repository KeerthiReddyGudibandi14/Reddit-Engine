-record(remove_post, {
    subreddit :: integer(),
    post :: integer(),
    reply_to :: gleam@erlang@process:subject({ok, engine@types:subreddit()} |
        {error, engine@types:engine_error()})
}).
