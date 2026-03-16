-record(create_comment, {
    author :: integer(),
    post :: integer(),
    parent :: gleam@option:option(integer()),
    body :: binary(),
    reply_to :: gleam@erlang@process:subject({ok, engine@types:comment()} |
        {error, engine@types:engine_error()})
}).
