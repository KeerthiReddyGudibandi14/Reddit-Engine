-record(engine, {
    supervisor :: gleam@erlang@process:subject(gleam@otp@supervisor:message()),
    services :: engine@supervisor:services()
}).
