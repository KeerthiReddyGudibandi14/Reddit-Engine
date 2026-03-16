-record(adjust_karma, {
    id :: integer(),
    delta :: integer(),
    reply_to :: gleam@erlang@process:subject({ok, engine@types:user()} |
        {error, engine@types:engine_error()})
}).
