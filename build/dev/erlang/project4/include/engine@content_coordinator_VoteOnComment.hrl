-record(vote_on_comment, {
    voter :: integer(),
    comment :: integer(),
    vote :: engine@types:vote(),
    reply_to :: gleam@erlang@process:subject({ok, engine@types:comment()} |
        {error, engine@types:engine_error()})
}).
