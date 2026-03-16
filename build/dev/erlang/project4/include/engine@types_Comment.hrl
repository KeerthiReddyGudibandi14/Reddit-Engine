-record(comment, {
    id :: integer(),
    post :: integer(),
    parent :: gleam@option:option(integer()),
    author :: integer(),
    body :: binary(),
    created_at :: integer(),
    score :: integer()
}).
