-record(vote_on_post, {
    voter :: integer(),
    post :: integer(),
    vote :: engine@types:vote(),
    reply_to :: gleam@erlang@process:subject({ok, engine@types:post()} |
        {error, engine@types:engine_error()})
}).
