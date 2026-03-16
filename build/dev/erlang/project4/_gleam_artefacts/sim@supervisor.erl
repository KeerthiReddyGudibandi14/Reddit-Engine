-module(sim@supervisor).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/sim/supervisor.gleam").
-export([start/1]).
-export_type([simulation/0, handles/0, builder/0]).

-type simulation() :: {simulation,
        gleam@erlang@process:subject(gleam@otp@supervisor:message()),
        handles()}.

-type handles() :: {handles,
        gleam@erlang@process:subject(sim@coordinator:message()),
        gleam@erlang@process:subject(sim@metrics_logger:message())}.

-type builder() :: {builder,
        gleam@erlang@process:subject(handles()),
        gleam@option:option(gleam@erlang@process:subject(sim@coordinator:message())),
        gleam@option:option(gleam@erlang@process:subject(sim@metrics_logger:message())),
        boolean()}.

-file("src/sim/supervisor.gleam", 70).
-spec new_builder(gleam@erlang@process:subject(handles())) -> builder().
new_builder(Reply) ->
    {builder, Reply, none, none, false}.

-file("src/sim/supervisor.gleam", 100).
-spec maybe_emit_handles(builder()) -> builder().
maybe_emit_handles(Builder) ->
    case Builder of
        {builder, Reply, {some, Coord}, {some, Logger}, false} ->
            gleam@erlang@process:send(Reply, {handles, Coord, Logger}),
            {builder, Reply, {some, Coord}, {some, Logger}, true};

        _ ->
            Builder
    end.

-file("src/sim/supervisor.gleam", 74).
-spec with_coordinator(
    builder(),
    gleam@erlang@process:subject(sim@coordinator:message())
) -> builder().
with_coordinator(Builder, Coordinator) ->
    _pipe = {builder,
        erlang:element(2, Builder),
        {some, Coordinator},
        erlang:element(4, Builder),
        erlang:element(5, Builder)},
    maybe_emit_handles(_pipe).

-file("src/sim/supervisor.gleam", 87).
-spec with_metrics_logger(
    builder(),
    gleam@erlang@process:subject(sim@metrics_logger:message())
) -> builder().
with_metrics_logger(Builder, Logger) ->
    _pipe = {builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        {some, Logger},
        erlang:element(5, Builder)},
    maybe_emit_handles(_pipe).

-file("src/sim/supervisor.gleam", 21).
-spec start(engine@supervisor:services()) -> {ok, simulation()} |
    {error, gleam@otp@actor:start_error()}.
start(Engine_services) ->
    Ack = gleam@erlang@process:new_subject(),
    Builder = new_builder(Ack),
    Metrics_spec = begin
        _pipe = gleam@otp@supervisor:worker(
            fun(_) -> sim@metrics_logger:start(<<"metrics.csv"/utf8>>) end
        ),
        gleam@otp@supervisor:returning(_pipe, fun with_metrics_logger/2)
    end,
    Coordinator_spec = begin
        _pipe@1 = gleam@otp@supervisor:worker(
            fun(Builder@1) -> case erlang:element(4, Builder@1) of
                    {some, Logger} ->
                        sim@coordinator:start_with(
                            Engine_services,
                            {some, Logger}
                        );

                    none ->
                        {error,
                            {init_failed,
                                {abnormal, <<"metrics logger missing"/utf8>>}}}
                end end
        ),
        gleam@otp@supervisor:returning(_pipe@1, fun with_coordinator/2)
    end,
    Init = fun(Children) -> _pipe@2 = Children,
        _pipe@3 = gleam@otp@supervisor:add(_pipe@2, Metrics_spec),
        gleam@otp@supervisor:add(_pipe@3, Coordinator_spec) end,
    case gleam@otp@supervisor:start_spec({spec, Builder, 5, 10, Init}) of
        {ok, Supervisor_subject} ->
            Handles = gleam_erlang_ffi:'receive'(Ack),
            {ok, {simulation, Supervisor_subject, Handles}};

        {error, Reason} ->
            {error, Reason}
    end.
