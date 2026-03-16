-record(services, {
    user_registry :: gleam@erlang@process:subject(engine@user_registry:message()),
    subreddit_registry :: gleam@erlang@process:subject(engine@subreddit_registry:message()),
    content_coordinator :: gleam@erlang@process:subject(engine@content_coordinator:message()),
    dm_router :: gleam@erlang@process:subject(engine@dm_router:message())
}).
