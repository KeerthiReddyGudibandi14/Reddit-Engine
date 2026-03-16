-record(register, {
    name :: binary(),
    reply_to :: gleam@erlang@process:subject({ok, engine@types:user()} |
        {error, engine@types:engine_error()})
}).
