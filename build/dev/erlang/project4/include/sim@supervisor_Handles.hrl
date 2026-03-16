-record(handles, {
    coordinator :: gleam@erlang@process:subject(sim@coordinator:message()),
    metrics_logger :: gleam@erlang@process:subject(sim@metrics_logger:message())
}).
