-module(sim@coordinator).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/sim/coordinator.gleam").
-export([start_with/2, start/1]).
-export_type([message/0, coordinator_error/0, simulation_config/0, client_registration/0, client_handle/0, metric_sample/0, metrics/0, simulation_snapshot/0, state/0]).

-type message() :: {configure,
        simulation_config(),
        gleam@erlang@process:subject({ok, nil} | {error, coordinator_error()})} |
    {register_client,
        client_registration(),
        gleam@erlang@process:subject({ok, client_handle()} |
            {error, coordinator_error()})} |
    {record_sample, binary(), metric_sample()} |
    {snapshot, gleam@erlang@process:subject(simulation_snapshot())} |
    shutdown.

-type coordinator_error() :: already_configured |
    not_configured |
    invalid_registration.

-type simulation_config() :: {simulation_config,
        integer(),
        integer(),
        integer()}.

-type client_registration() :: {client_registration, binary()}.

-type client_handle() :: {client_handle, integer(), binary()}.

-type metric_sample() :: {operation_recorded, binary()} |
    {event_recorded, binary()}.

-type metrics() :: {metrics, integer(), integer()}.

-type simulation_snapshot() :: {simulation_snapshot,
        gleam@option:option(simulation_config()),
        integer(),
        metrics()}.

-type state() :: {state,
        engine@supervisor:services(),
        gleam@option:option(simulation_config()),
        gleam@dict:dict(integer(), client_handle()),
        integer(),
        metrics(),
        gleam@option:option(gleam@erlang@process:subject(sim@metrics_logger:message()))}.

-file("src/sim/coordinator.gleam", 107).
-spec configure(
    simulation_config(),
    gleam@erlang@process:subject({ok, nil} | {error, coordinator_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
configure(Config, Reply, State) ->
    case erlang:element(3, State) of
        {some, _} ->
            gleam@erlang@process:send(Reply, {error, already_configured}),
            gleam@otp@actor:continue(State);

        none ->
            gleam@erlang@process:send(Reply, {ok, nil}),
            gleam@otp@actor:continue(
                {state,
                    erlang:element(2, State),
                    {some, Config},
                    erlang:element(4, State),
                    erlang:element(5, State),
                    erlang:element(6, State),
                    erlang:element(7, State)}
            )
    end.

-file("src/sim/coordinator.gleam", 132).
-spec register_client(
    client_registration(),
    gleam@erlang@process:subject({ok, client_handle()} |
        {error, coordinator_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
register_client(Registration, Reply, State) ->
    case erlang:element(3, State) of
        none ->
            gleam@erlang@process:send(Reply, {error, not_configured}),
            gleam@otp@actor:continue(State);

        {some, _} ->
            case Registration of
                {client_registration, Label} ->
                    case gleam@string:is_empty(Label) of
                        true ->
                            gleam@erlang@process:send(
                                Reply,
                                {error, invalid_registration}
                            ),
                            gleam@otp@actor:continue(State);

                        false ->
                            Handle = {client_handle,
                                erlang:element(5, State),
                                Label},
                            Clients = gleam@dict:insert(
                                erlang:element(4, State),
                                erlang:element(2, Handle),
                                Handle
                            ),
                            gleam@erlang@process:send(Reply, {ok, Handle}),
                            gleam@otp@actor:continue(
                                {state,
                                    erlang:element(2, State),
                                    erlang:element(3, State),
                                    Clients,
                                    erlang:element(5, State) + 1,
                                    erlang:element(6, State),
                                    erlang:element(7, State)}
                            )
                    end
            end
    end.

-file("src/sim/coordinator.gleam", 189).
-spec snapshot(gleam@erlang@process:subject(simulation_snapshot()), state()) -> gleam@otp@actor:next(message(), state()).
snapshot(Reply, State) ->
    gleam@erlang@process:send(
        Reply,
        {simulation_snapshot,
            erlang:element(3, State),
            maps:size(erlang:element(4, State)),
            erlang:element(6, State)}
    ),
    gleam@otp@actor:continue(State).

-file("src/sim/coordinator.gleam", 215).
-spec maybe_flush_logger(state()) -> nil.
maybe_flush_logger(State) ->
    case erlang:element(7, State) of
        {some, Subject} ->
            _ = gleam@erlang@process:try_call(
                Subject,
                fun(Responder) -> {flush, Responder} end,
                2000
            ),
            nil;

        none ->
            nil
    end.

-file("src/sim/coordinator.gleam", 228).
-spec metric_kind(metric_sample()) -> binary().
metric_kind(Sample) ->
    case Sample of
        {operation_recorded, Kind} ->
            Kind;

        {event_recorded, Kind@1} ->
            Kind@1
    end.

-file("src/sim/coordinator.gleam", 204).
-spec maybe_log_sample(
    gleam@option:option(gleam@erlang@process:subject(sim@metrics_logger:message())),
    binary(),
    metric_sample()
) -> nil.
maybe_log_sample(Logger, Source, Sample) ->
    case Logger of
        {some, Subject} ->
            gleam@erlang@process:send(
                Subject,
                {record, Source, metric_kind(Sample)}
            );

        none ->
            nil
    end.

-file("src/sim/coordinator.gleam", 170).
-spec record_sample(binary(), metric_sample(), state()) -> state().
record_sample(Source, Sample, State) ->
    Metrics = case Sample of
        {operation_recorded, _} ->
            {metrics,
                erlang:element(2, erlang:element(6, State)) + 1,
                erlang:element(3, erlang:element(6, State))};

        {event_recorded, _} ->
            {metrics,
                erlang:element(2, erlang:element(6, State)),
                erlang:element(3, erlang:element(6, State)) + 1}
    end,
    maybe_log_sample(erlang:element(7, State), Source, Sample),
    {state,
        erlang:element(2, State),
        erlang:element(3, State),
        erlang:element(4, State),
        erlang:element(5, State),
        Metrics,
        erlang:element(7, State)}.

-file("src/sim/coordinator.gleam", 93).
-spec handle_message(message(), state()) -> gleam@otp@actor:next(message(), state()).
handle_message(Message, State) ->
    case Message of
        {configure, Config, Reply} ->
            configure(Config, Reply, State);

        {register_client, Registration, Reply@1} ->
            register_client(Registration, Reply@1, State);

        {record_sample, Source, Sample} ->
            gleam@otp@actor:continue(record_sample(Source, Sample, State));

        {snapshot, Reply@2} ->
            snapshot(Reply@2, State);

        shutdown ->
            maybe_flush_logger(State),
            {stop, normal}
    end.

-file("src/sim/coordinator.gleam", 65).
-spec start_with(
    engine@supervisor:services(),
    gleam@option:option(gleam@erlang@process:subject(sim@metrics_logger:message()))
) -> {ok, gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start_with(Engine_services, Logger) ->
    gleam@otp@actor:start(
        {state, Engine_services, none, maps:new(), 1, {metrics, 0, 0}, Logger},
        fun handle_message/2
    ).

-file("src/sim/coordinator.gleam", 61).
-spec start(engine@supervisor:services()) -> {ok,
        gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start(Engine_services) ->
    start_with(Engine_services, none).
