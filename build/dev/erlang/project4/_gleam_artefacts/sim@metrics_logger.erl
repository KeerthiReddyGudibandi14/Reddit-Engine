-module(sim@metrics_logger).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/sim/metrics_logger.gleam").
-export([start/1]).
-export_type([message/0, metric_entry/0, state/0]).

-type message() :: {record, binary(), binary()} |
    {flush,
        gleam@erlang@process:subject({ok, nil} |
            {error, gleam@erlang@atom:atom_()})} |
    {shutdown,
        gleam@erlang@process:subject({ok, nil} |
            {error, gleam@erlang@atom:atom_()})}.

-type metric_entry() :: {metric_entry, integer(), binary(), binary()}.

-type state() :: {state, binary(), list(metric_entry()), boolean()}.

-file("src/sim/metrics_logger.gleam", 46).
-spec add_entry(state(), binary(), binary()) -> state().
add_entry(State, Source, Kind) ->
    Entry = {metric_entry, os:system_time(millisecond), Source, Kind},
    {state,
        erlang:element(2, State),
        [Entry | erlang:element(3, State)],
        erlang:element(4, State)}.

-file("src/sim/metrics_logger.gleam", 107).
-spec normalize_write_result({ok, nil} | {error, gleam@erlang@atom:atom_()}) -> {ok,
        nil} |
    {error, gleam@erlang@atom:atom_()}.
normalize_write_result(Result) ->
    case Result of
        {error, Reason} ->
            {error, Reason};

        _ ->
            {ok, nil}
    end.

-file("src/sim/metrics_logger.gleam", 97).
-spec write_header(binary()) -> {ok, nil} | {error, gleam@erlang@atom:atom_()}.
write_header(Path) ->
    normalize_write_result(
        file:write_file(
            Path,
            <<"timestamp,source,kind\n"/utf8>>,
            [erlang:binary_to_atom(<<"write"/utf8>>),
                erlang:binary_to_atom(<<"binary"/utf8>>)]
        )
    ).

-file("src/sim/metrics_logger.gleam", 124).
-spec join_lines(list(binary())) -> binary().
join_lines(Lines) ->
    gleam@list:fold(Lines, <<""/utf8>>, fun(Acc, Line) -> case Acc of
                <<""/utf8>> ->
                    Line;

                _ ->
                    erlang:list_to_binary([Acc, <<"\n"/utf8>>, Line])
            end end).

-file("src/sim/metrics_logger.gleam", 137).
-spec escape(binary()) -> binary().
escape(Text) ->
    case gleam_stdlib:contains_string(Text, <<","/utf8>>) of
        false ->
            Text;

        true ->
            erlang:list_to_binary(
                [<<"\""/utf8>>,
                    gleam@string:replace(Text, <<"\""/utf8>>, <<"\"\""/utf8>>),
                    <<"\""/utf8>>]
            )
    end.

-file("src/sim/metrics_logger.gleam", 114).
-spec format_entry(metric_entry()) -> binary().
format_entry(Entry) ->
    erlang:list_to_binary(
        [erlang:integer_to_binary(erlang:element(2, Entry)),
            <<","/utf8>>,
            escape(erlang:element(3, Entry)),
            <<","/utf8>>,
            escape(erlang:element(4, Entry))]
    ).

-file("src/sim/metrics_logger.gleam", 77).
-spec flush_to_disk(state()) -> {ok, nil} | {error, gleam@erlang@atom:atom_()}.
flush_to_disk(State) ->
    case lists:reverse(erlang:element(3, State)) of
        [] ->
            {ok, nil};

        Entries ->
            Lines = begin
                _pipe = Entries,
                gleam@list:map(_pipe, fun format_entry/1)
            end,
            Csv_body = <<(join_lines(Lines))/binary, "\n"/utf8>>,
            normalize_write_result(
                file:write_file(
                    erlang:element(2, State),
                    Csv_body,
                    [erlang:binary_to_atom(<<"append"/utf8>>),
                        erlang:binary_to_atom(<<"binary"/utf8>>)]
                )
            )
    end.

-file("src/sim/metrics_logger.gleam", 51).
-spec flush(
    gleam@erlang@process:subject({ok, nil} | {error, gleam@erlang@atom:atom_()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
flush(Reply, State) ->
    case flush_to_disk(State) of
        {ok, _} ->
            gleam@erlang@process:send(Reply, {ok, nil}),
            gleam@otp@actor:continue(
                {state, erlang:element(2, State), [], erlang:element(4, State)}
            );

        {error, Reason} ->
            gleam@erlang@process:send(Reply, {error, Reason}),
            gleam@otp@actor:continue(State)
    end.

-file("src/sim/metrics_logger.gleam", 68).
-spec shutdown(
    gleam@erlang@process:subject({ok, nil} | {error, gleam@erlang@atom:atom_()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
shutdown(Reply, State) ->
    Result = flush_to_disk(State),
    gleam@erlang@process:send(Reply, Result),
    {stop, normal}.

-file("src/sim/metrics_logger.gleam", 38).
-spec handle_message(message(), state()) -> gleam@otp@actor:next(message(), state()).
handle_message(Message, State) ->
    case Message of
        {record, Source, Kind} ->
            gleam@otp@actor:continue(add_entry(State, Source, Kind));

        {flush, Reply} ->
            flush(Reply, State);

        {shutdown, Reply@1} ->
            shutdown(Reply@1, State)
    end.

-file("src/sim/metrics_logger.gleam", 22).
-spec start(binary()) -> {ok, gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start(Path) ->
    _ = write_header(Path),
    gleam@otp@actor:start({state, Path, [], true}, fun handle_message/2).
