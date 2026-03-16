-record(simulation_snapshot, {
    config :: gleam@option:option(sim@coordinator:simulation_config()),
    client_count :: integer(),
    metrics :: sim@coordinator:metrics()
}).
