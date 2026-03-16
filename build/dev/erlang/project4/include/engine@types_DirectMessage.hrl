-record(direct_message, {
    id :: integer(),
    thread :: integer(),
    sender :: integer(),
    recipient :: integer(),
    body :: binary(),
    created_at :: integer(),
    in_reply_to :: gleam@option:option(integer())
}).
