-record(list_thread, {
    thread :: integer(),
    requester :: integer(),
    reply_to :: gleam@erlang@process:subject({ok,
            list(engine@types:direct_message())} |
        {error, engine@types:engine_error()})
}).
