-module(project4).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/project4.gleam").
-export([main/0]).
-export_type([cli_config/0]).

-type cli_config() :: {cli_config,
        integer(),
        integer(),
        list(binary()),
        binary()}.

-file("src/project4.gleam", 39).
-spec default_cli_config() -> cli_config().
default_cli_config() ->
    {cli_config,
        10,
        30,
        [<<"general"/utf8>>, <<"technology"/utf8>>],
        <<"Hello from Gleam simulation!"/utf8>>}.

-file("src/project4.gleam", 75).
-spec parse_home_subreddits(binary()) -> list(binary()).
parse_home_subreddits(Value) ->
    Subs = begin
        _pipe = Value,
        _pipe@1 = gleam@string:split(_pipe, <<","/utf8>>),
        _pipe@2 = gleam@list:map(_pipe@1, fun gleam@string:trim/1),
        gleam@list:filter(_pipe@2, fun(Name) -> Name /= <<""/utf8>> end)
    end,
    case Subs of
        [] ->
            [<<"general"/utf8>>];

        _ ->
            Subs
    end.

-file("src/project4.gleam", 52).
-spec parse_arg(cli_config(), binary()) -> cli_config().
parse_arg(Config, Arg) ->
    case gleam@string:split_once(Arg, <<"="/utf8>>) of
        {ok, {<<"--clients"/utf8>>, Value}} ->
            case gleam_stdlib:parse_int(Value) of
                {ok, Parsed} ->
                    {cli_config,
                        gleam@int:max(Parsed, 0),
                        erlang:element(3, Config),
                        erlang:element(4, Config),
                        erlang:element(5, Config)};

                {error, _} ->
                    Config
            end;

        {ok, {<<"--ticks"/utf8>>, Value@1}} ->
            case gleam_stdlib:parse_int(Value@1) of
                {ok, Parsed@1} ->
                    {cli_config,
                        erlang:element(2, Config),
                        gleam@int:max(Parsed@1, 0),
                        erlang:element(4, Config),
                        erlang:element(5, Config)};

                {error, _} ->
                    Config
            end;

        {ok, {<<"--home"/utf8>>, Value@2}} ->
            {cli_config,
                erlang:element(2, Config),
                erlang:element(3, Config),
                parse_home_subreddits(Value@2),
                erlang:element(5, Config)};

        {ok, {<<"--post"/utf8>>, Value@3}} ->
            {cli_config,
                erlang:element(2, Config),
                erlang:element(3, Config),
                erlang:element(4, Config),
                Value@3};

        _ ->
            Config
    end.

-file("src/project4.gleam", 48).
-spec parse_args(list(binary())) -> cli_config().
parse_args(Args) ->
    gleam@list:fold(Args, default_cli_config(), fun parse_arg/2).

-file("src/project4.gleam", 149).
-spec coordinator_error_to_string(sim@coordinator:coordinator_error()) -> binary().
coordinator_error_to_string(Error) ->
    case Error of
        already_configured ->
            <<"Coordinator already configured"/utf8>>;

        not_configured ->
            <<"Coordinator not configured"/utf8>>;

        invalid_registration ->
            <<"Invalid client registration"/utf8>>
    end.

-file("src/project4.gleam", 216).
-spec run_ticks(
    list(gleam@erlang@process:subject(sim@client:message())),
    integer()
) -> nil.
run_ticks(Subjects, Ticks) ->
    case Ticks =< 0 of
        true ->
            nil;

        false ->
            gleam@list:each(
                Subjects,
                fun(Subject) -> gleam@erlang@process:send(Subject, tick) end
            ),
            run_ticks(Subjects, Ticks - 1)
    end.

-file("src/project4.gleam", 241).
-spec print_snapshot(sim@coordinator:simulation_snapshot()) -> nil.
print_snapshot(Snapshot) ->
    gleam_stdlib:println(
        erlang:list_to_binary(
            [<<"Coordinator reports "/utf8>>,
                erlang:integer_to_binary(erlang:element(3, Snapshot)),
                <<" registered clients"/utf8>>]
        )
    ),
    gleam_stdlib:println(
        erlang:list_to_binary(
            [<<"Operations recorded: "/utf8>>,
                erlang:integer_to_binary(
                    erlang:element(2, erlang:element(4, Snapshot))
                )]
        )
    ),
    gleam_stdlib:println(
        erlang:list_to_binary(
            [<<"Events recorded: "/utf8>>,
                erlang:integer_to_binary(
                    erlang:element(3, erlang:element(4, Snapshot))
                )]
        )
    ).

-file("src/project4.gleam", 263).
-spec call_error_to_string(binary(), gleam@erlang@process:call_error(any())) -> binary().
call_error_to_string(Context, Error) ->
    case Error of
        {callee_down, _} ->
            erlang:list_to_binary(
                [<<"Failed to "/utf8>>,
                    Context,
                    <<": coordinator process exited"/utf8>>]
            );

        call_timeout ->
            erlang:list_to_binary(
                [<<"Failed to "/utf8>>, Context, <<": call timed out"/utf8>>]
            )
    end.

-file("src/project4.gleam", 130).
-spec configure_coordinator(
    gleam@erlang@process:subject(sim@coordinator:message()),
    sim@coordinator:simulation_config()
) -> {ok, nil} | {error, binary()}.
configure_coordinator(Coordinator_subject, Config) ->
    case gleam@erlang@process:try_call(
        Coordinator_subject,
        fun(Responder) -> {configure, Config, Responder} end,
        1000
    ) of
        {ok, Result} ->
            case Result of
                {ok, _} ->
                    {ok, nil};

                {error, Error} ->
                    {error, coordinator_error_to_string(Error)}
            end;

        {error, Call_error} ->
            {error,
                call_error_to_string(
                    <<"configure coordinator"/utf8>>,
                    Call_error
                )}
    end.

-file("src/project4.gleam", 194).
-spec register_client(
    gleam@erlang@process:subject(sim@coordinator:message()),
    binary()
) -> {ok, sim@coordinator:client_handle()} | {error, binary()}.
register_client(Coordinator_subject, Label) ->
    case gleam@erlang@process:try_call(
        Coordinator_subject,
        fun(Responder) ->
            {register_client, {client_registration, Label}, Responder}
        end,
        1000
    ) of
        {ok, Register_result} ->
            case Register_result of
                {ok, Handle} ->
                    {ok, Handle};

                {error, Error} ->
                    {error, coordinator_error_to_string(Error)}
            end;

        {error, Call_error} ->
            {error,
                call_error_to_string(<<"register client"/utf8>>, Call_error)}
    end.

-file("src/project4.gleam", 157).
-spec start_clients(
    cli_config(),
    engine@supervisor:services(),
    gleam@erlang@process:subject(sim@coordinator:message())
) -> list(gleam@erlang@process:subject(sim@client:message())).
start_clients(Config, Engine_services, Coordinator_subject) ->
    Client_config = {client_config,
        <<"sim-user"/utf8>>,
        erlang:element(4, Config),
        erlang:element(5, Config)},
    Client_ids = case erlang:element(2, Config) =< 0 of
        true ->
            [];

        false ->
            gleam@list:range(1, erlang:element(2, Config))
    end,
    _pipe = Client_ids,
    _pipe@1 = gleam@list:fold(
        _pipe,
        [],
        fun(Acc, Id) ->
            Label = erlang:list_to_binary(
                [<<"client-"/utf8>>, erlang:integer_to_binary(Id)]
            ),
            case register_client(Coordinator_subject, Label) of
                {ok, Handle} ->
                    case sim@client:start(
                        erlang:element(2, Handle),
                        erlang:element(3, Handle),
                        Engine_services,
                        Coordinator_subject,
                        Client_config
                    ) of
                        {ok, Subject} ->
                            gleam@erlang@process:send(Subject, 'begin'),
                            [Subject | Acc];

                        {error, _} ->
                            Acc
                    end;

                {error, _} ->
                    Acc
            end
        end
    ),
    lists:reverse(_pipe@1).

-file("src/project4.gleam", 228).
-spec report_snapshot(gleam@erlang@process:subject(sim@coordinator:message())) -> nil.
report_snapshot(Coordinator_subject) ->
    case gleam@erlang@process:try_call(
        Coordinator_subject,
        fun(Responder) -> {snapshot, Responder} end,
        1000
    ) of
        {ok, Snapshot} ->
            print_snapshot(Snapshot);

        {error, Call_error} ->
            gleam_stdlib:println(
                call_error_to_string(<<"retrieve snapshot"/utf8>>, Call_error)
            )
    end.

-file("src/project4.gleam", 291).
-spec metrics_file_error(binary(), gleam@erlang@atom:atom_()) -> binary().
metrics_file_error(Context, Reason) ->
    erlang:list_to_binary(
        [<<"Failed to "/utf8>>,
            Context,
            <<": "/utf8>>,
            erlang:atom_to_binary(Reason)]
    ).

-file("src/project4.gleam", 273).
-spec flush_metrics_logger(
    gleam@erlang@process:subject(sim@metrics_logger:message())
) -> {ok, nil} | {error, binary()}.
flush_metrics_logger(Logger) ->
    case gleam@erlang@process:try_call(
        Logger,
        fun(Responder) -> {flush, Responder} end,
        2000
    ) of
        {ok, Result} ->
            case Result of
                {ok, _} ->
                    {ok, nil};

                {error, Reason} ->
                    {error,
                        metrics_file_error(
                            <<"flush metrics logger"/utf8>>,
                            Reason
                        )}
            end;

        {error, Call_error} ->
            {error,
                call_error_to_string(
                    <<"flush metrics logger"/utf8>>,
                    Call_error
                )}
    end.

-file("src/project4.gleam", 88).
-spec run_simulation(cli_config()) -> nil.
run_simulation(Config) ->
    case engine@supervisor:start() of
        {ok, {engine, _, Services}} ->
            case sim@supervisor:start(Services) of
                {ok, {simulation, _, Handles}} ->
                    Simulation_config = {simulation_config,
                        erlang:element(2, Config),
                        25,
                        gleam@int:absolute_value(os:system_time(millisecond))},
                    case configure_coordinator(
                        erlang:element(2, Handles),
                        Simulation_config
                    ) of
                        {ok, nil} ->
                            Client_subjects = start_clients(
                                Config,
                                Services,
                                erlang:element(2, Handles)
                            ),
                            run_ticks(
                                Client_subjects,
                                erlang:element(3, Config)
                            ),
                            gleam@list:each(
                                Client_subjects,
                                fun(Subject) ->
                                    gleam@erlang@process:send(Subject, shutdown)
                                end
                            ),
                            gleam_erlang_ffi:sleep(300),
                            case flush_metrics_logger(
                                erlang:element(3, Handles)
                            ) of
                                {ok, _} ->
                                    nil;

                                {error, Message} ->
                                    gleam_stdlib:println(
                                        erlang:list_to_binary(
                                            [<<"Warning: "/utf8>>, Message]
                                        )
                                    )
                            end,
                            report_snapshot(erlang:element(2, Handles)),
                            gleam@erlang@process:send(
                                erlang:element(2, Handles),
                                shutdown
                            ),
                            gleam_erlang_ffi:sleep(100),
                            gleam_stdlib:println(
                                <<"Simulation complete. Metrics appended to metrics.csv"/utf8>>
                            );

                        {error, Message@1} ->
                            gleam_stdlib:println(Message@1)
                    end;

                {error, _} ->
                    gleam_stdlib:println(
                        <<"Failed to start simulator supervisor"/utf8>>
                    )
            end;

        {error, _} ->
            gleam_stdlib:println(<<"Failed to start engine supervisor"/utf8>>)
    end.

-file("src/project4.gleam", 15).
-spec main() -> nil.
main() ->
    Args = argv:load(),
    Cli_config = parse_args(erlang:element(4, Args)),
    gleam_stdlib:println(
        erlang:list_to_binary(
            [<<"Starting simulation with "/utf8>>,
                erlang:integer_to_binary(erlang:element(2, Cli_config)),
                <<" clients for "/utf8>>,
                erlang:integer_to_binary(erlang:element(3, Cli_config)),
                <<" ticks per client"/utf8>>]
        )
    ),
    run_simulation(Cli_config).
