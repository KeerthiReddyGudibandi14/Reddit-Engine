-module(engine@supervisor).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/engine/supervisor.gleam").
-export([start/0]).
-export_type([engine/0, services/0, builder/0]).

-type engine() :: {engine,
        gleam@erlang@process:subject(gleam@otp@supervisor:message()),
        services()}.

-type services() :: {services,
        gleam@erlang@process:subject(engine@user_registry:message()),
        gleam@erlang@process:subject(engine@subreddit_registry:message()),
        gleam@erlang@process:subject(engine@content_coordinator:message()),
        gleam@erlang@process:subject(engine@dm_router:message())}.

-type builder() :: {builder,
        gleam@erlang@process:subject(services()),
        gleam@option:option(gleam@erlang@process:subject(engine@user_registry:message())),
        gleam@option:option(gleam@erlang@process:subject(engine@subreddit_registry:message())),
        gleam@option:option(gleam@erlang@process:subject(engine@content_coordinator:message())),
        gleam@option:option(gleam@erlang@process:subject(engine@dm_router:message())),
        boolean()}.

-file("src/engine/supervisor.gleam", 98).
-spec new_builder(gleam@erlang@process:subject(services())) -> builder().
new_builder(Reply) ->
    {builder, Reply, none, none, none, none, false}.

-file("src/engine/supervisor.gleam", 169).
-spec maybe_emit_service_handles(builder()) -> builder().
maybe_emit_service_handles(Builder) ->
    case Builder of
        {builder,
            Reply,
            {some, User_reg},
            {some, Sub_reg},
            {some, Content},
            {some, Dm},
            false} ->
            gleam@erlang@process:send(
                Reply,
                {services, User_reg, Sub_reg, Content, Dm}
            ),
            {builder,
                Reply,
                {some, User_reg},
                {some, Sub_reg},
                {some, Content},
                {some, Dm},
                true};

        _ ->
            Builder
    end.

-file("src/engine/supervisor.gleam", 109).
-spec with_user_registry(
    builder(),
    gleam@erlang@process:subject(engine@user_registry:message())
) -> builder().
with_user_registry(Builder, Registry) ->
    _pipe = {builder,
        erlang:element(2, Builder),
        {some, Registry},
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder),
        erlang:element(7, Builder)},
    maybe_emit_service_handles(_pipe).

-file("src/engine/supervisor.gleam", 124).
-spec with_subreddit_registry(
    builder(),
    gleam@erlang@process:subject(engine@subreddit_registry:message())
) -> builder().
with_subreddit_registry(Builder, Registry) ->
    _pipe = {builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        {some, Registry},
        erlang:element(5, Builder),
        erlang:element(6, Builder),
        erlang:element(7, Builder)},
    maybe_emit_service_handles(_pipe).

-file("src/engine/supervisor.gleam", 139).
-spec with_content_coordinator(
    builder(),
    gleam@erlang@process:subject(engine@content_coordinator:message())
) -> builder().
with_content_coordinator(Builder, Coordinator) ->
    _pipe = {builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        {some, Coordinator},
        erlang:element(6, Builder),
        erlang:element(7, Builder)},
    maybe_emit_service_handles(_pipe).

-file("src/engine/supervisor.gleam", 154).
-spec with_dm_router(
    builder(),
    gleam@erlang@process:subject(engine@dm_router:message())
) -> builder().
with_dm_router(Builder, Router) ->
    _pipe = {builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        {some, Router},
        erlang:element(7, Builder)},
    maybe_emit_service_handles(_pipe).

-file("src/engine/supervisor.gleam", 28).
-spec start() -> {ok, engine()} | {error, gleam@otp@actor:start_error()}.
start() ->
    Ack = gleam@erlang@process:new_subject(),
    Builder = new_builder(Ack),
    User_spec = begin
        _pipe = gleam@otp@supervisor:worker(
            fun(_) -> engine@user_registry:start() end
        ),
        gleam@otp@supervisor:returning(_pipe, fun with_user_registry/2)
    end,
    Subreddit_spec = begin
        _pipe@1 = gleam@otp@supervisor:worker(
            fun(Builder@1) -> case erlang:element(3, Builder@1) of
                    {some, User_reg} ->
                        engine@subreddit_registry:start(User_reg);

                    none ->
                        {error,
                            {init_failed,
                                {abnormal, <<"user registry unavailable"/utf8>>}}}
                end end
        ),
        gleam@otp@supervisor:returning(_pipe@1, fun with_subreddit_registry/2)
    end,
    Content_spec = begin
        _pipe@2 = gleam@otp@supervisor:worker(
            fun(Builder@2) ->
                case {erlang:element(3, Builder@2),
                    erlang:element(4, Builder@2)} of
                    {{some, User_reg@1}, {some, Sub_reg}} ->
                        engine@content_coordinator:start(User_reg@1, Sub_reg);

                    {_, _} ->
                        {error,
                            {init_failed,
                                {abnormal,
                                    <<"content coordinator dependencies missing"/utf8>>}}}
                end
            end
        ),
        gleam@otp@supervisor:returning(_pipe@2, fun with_content_coordinator/2)
    end,
    Dm_spec = begin
        _pipe@3 = gleam@otp@supervisor:worker(
            fun(_) -> engine@dm_router:start() end
        ),
        gleam@otp@supervisor:returning(_pipe@3, fun with_dm_router/2)
    end,
    Init = fun(Children) -> _pipe@4 = Children,
        _pipe@5 = gleam@otp@supervisor:add(_pipe@4, User_spec),
        _pipe@6 = gleam@otp@supervisor:add(_pipe@5, Subreddit_spec),
        _pipe@7 = gleam@otp@supervisor:add(_pipe@6, Content_spec),
        gleam@otp@supervisor:add(_pipe@7, Dm_spec) end,
    case gleam@otp@supervisor:start_spec({spec, Builder, 5, 10, Init}) of
        {ok, Subject} ->
            Services = gleam_erlang_ffi:'receive'(Ack),
            {ok, {engine, Subject, Services}};

        {error, Reason} ->
            {error, Reason}
    end.
