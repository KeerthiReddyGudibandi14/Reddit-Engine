-record(send_new, {
    from :: integer(),
    to :: integer(),
    body :: binary(),
    reply_to :: gleam@erlang@process:subject({ok, engine@types:direct_message()} |
        {error, engine@types:engine_error()})
}).
