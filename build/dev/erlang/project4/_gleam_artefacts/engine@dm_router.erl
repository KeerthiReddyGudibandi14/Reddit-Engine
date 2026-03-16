-module(engine@dm_router).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/engine/dm_router.gleam").
-export([start_with/2, start/0]).
-export_type([message/0, thread_store/0, state/0]).

-type message() :: {send_new,
        integer(),
        integer(),
        binary(),
        gleam@erlang@process:subject({ok, engine@types:direct_message()} |
            {error, engine@types:engine_error()})} |
    {reply,
        integer(),
        integer(),
        binary(),
        gleam@erlang@process:subject({ok, engine@types:direct_message()} |
            {error, engine@types:engine_error()})} |
    {list_inbox,
        integer(),
        gleam@erlang@process:subject(list(engine@types:direct_message()))} |
    {list_thread,
        integer(),
        integer(),
        gleam@erlang@process:subject({ok, list(engine@types:direct_message())} |
            {error, engine@types:engine_error()})} |
    shutdown.

-type thread_store() :: {thread_store,
        gleam@set:set(integer()),
        list(integer())}.

-type state() :: {state,
        gleam@dict:dict(integer(), thread_store()),
        gleam@dict:dict(integer(), engine@types:direct_message()),
        gleam@dict:dict(integer(), list(integer())),
        engine@ids:id_generator(integer()),
        engine@ids:id_generator(integer())}.

-file("src/engine/dm_router.gleam", 243).
-spec update_threads(
    state(),
    gleam@dict:dict(integer(), thread_store()),
    engine@ids:id_generator(integer())
) -> state().
update_threads(State, Threads, Thread_ids) ->
    {state,
        Threads,
        erlang:element(3, State),
        erlang:element(4, State),
        Thread_ids,
        erlang:element(6, State)}.

-file("src/engine/dm_router.gleam", 266).
-spec other_participant(gleam@set:set(integer()), integer()) -> {ok, integer()} |
    {error, engine@types:engine_error()}.
other_participant(Participants, Sender) ->
    _pipe = Participants,
    _pipe@1 = gleam@set:to_list(_pipe),
    _pipe@2 = gleam@list:filter(_pipe@1, fun(User) -> User /= Sender end),
    _pipe@3 = gleam@list:first(_pipe@2),
    gleam@result:map_error(_pipe@3, fun(_) -> invalid_state end).

-file("src/engine/dm_router.gleam", 277).
-spec compare_desc(integer(), integer()) -> gleam@order:order().
compare_desc(A, B) ->
    case gleam@int:compare(A, B) of
        lt ->
            gt;

        eq ->
            eq;

        gt ->
            lt
    end.

-file("src/engine/dm_router.gleam", 285).
-spec compare_asc(integer(), integer()) -> gleam@order:order().
compare_asc(A, B) ->
    gleam@int:compare(A, B).

-file("src/engine/dm_router.gleam", 181).
-spec list_thread(
    integer(),
    integer(),
    gleam@erlang@process:subject({ok, list(engine@types:direct_message())} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
list_thread(Thread, Requester, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(2, State), Thread) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, {thread_store, Participants, Message_ids}} ->
            case gleam@set:contains(Participants, Requester) of
                false ->
                    gleam@erlang@process:send(Reply, {error, permission_denied}),
                    gleam@otp@actor:continue(State);

                true ->
                    Messages = begin
                        _pipe = Message_ids,
                        _pipe@1 = gleam@list:filter_map(
                            _pipe,
                            fun(Id) ->
                                gleam_stdlib:map_get(
                                    erlang:element(3, State),
                                    Id
                                )
                            end
                        ),
                        gleam@list:sort(
                            _pipe@1,
                            fun(A, B) ->
                                compare_asc(
                                    erlang:element(7, A),
                                    erlang:element(7, B)
                                )
                            end
                        )
                    end,
                    gleam@erlang@process:send(Reply, {ok, Messages}),
                    gleam@otp@actor:continue(State)
            end
    end.

-file("src/engine/dm_router.gleam", 289).
-spec result_to_list({ok, list(integer())} | {error, nil}, list(integer())) -> list(integer()).
result_to_list(Result, Default) ->
    case Result of
        {ok, Value} ->
            Value;

        {error, _} ->
            Default
    end.

-file("src/engine/dm_router.gleam", 167).
-spec list_inbox(
    integer(),
    gleam@erlang@process:subject(list(engine@types:direct_message())),
    state()
) -> gleam@otp@actor:next(message(), state()).
list_inbox(User, Reply, State) ->
    Message_ids = begin
        _pipe = gleam_stdlib:map_get(erlang:element(4, State), User),
        result_to_list(_pipe, [])
    end,
    Messages = begin
        _pipe@1 = Message_ids,
        _pipe@2 = gleam@list:filter_map(
            _pipe@1,
            fun(Id) -> gleam_stdlib:map_get(erlang:element(3, State), Id) end
        ),
        gleam@list:sort(
            _pipe@2,
            fun(A, B) ->
                compare_desc(erlang:element(7, A), erlang:element(7, B))
            end
        )
    end,
    gleam@erlang@process:send(Reply, Messages),
    gleam@otp@actor:continue(State).

-file("src/engine/dm_router.gleam", 257).
-spec update_inbox(
    gleam@dict:dict(integer(), list(integer())),
    integer(),
    integer()
) -> gleam@dict:dict(integer(), list(integer())).
update_inbox(Inbox, User, Message_id) ->
    Existing = begin
        _pipe = gleam_stdlib:map_get(Inbox, User),
        result_to_list(_pipe, [])
    end,
    gleam@dict:insert(Inbox, User, [Message_id | Existing]).

-file("src/engine/dm_router.gleam", 212).
-spec create_message(
    integer(),
    gleam@option:option(integer()),
    integer(),
    integer(),
    binary(),
    state()
) -> {engine@types:direct_message(), state()}.
create_message(Thread, In_reply_to, From, To, Body, State) ->
    {Message_id, Next_message_ids} = engine@ids:next(erlang:element(6, State)),
    Timestamp = os:system_time(millisecond),
    Message = {direct_message,
        Message_id,
        Thread,
        From,
        To,
        Body,
        Timestamp,
        In_reply_to},
    Messages = gleam@dict:insert(erlang:element(3, State), Message_id, Message),
    Inbox_from = update_inbox(erlang:element(4, State), From, Message_id),
    Inbox = update_inbox(Inbox_from, To, Message_id),
    {Message,
        {state,
            erlang:element(2, State),
            Messages,
            Inbox,
            erlang:element(5, State),
            Next_message_ids}}.

-file("src/engine/dm_router.gleam", 88).
-spec send_new(
    integer(),
    integer(),
    binary(),
    gleam@erlang@process:subject({ok, engine@types:direct_message()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
send_new(From, To, Body, Reply, State) ->
    case From =:= To of
        true ->
            gleam@erlang@process:send(Reply, {error, invalid_state}),
            gleam@otp@actor:continue(State);

        false ->
            {Thread_id, Next_thread_ids} = engine@ids:next(
                erlang:element(5, State)
            ),
            {Message, State@1} = create_message(
                Thread_id,
                none,
                From,
                To,
                Body,
                State
            ),
            Threads = gleam@dict:insert(
                erlang:element(2, State@1),
                Thread_id,
                {thread_store,
                    gleam@set:from_list([From, To]),
                    [erlang:element(2, Message)]}
            ),
            gleam@erlang@process:send(Reply, {ok, Message}),
            gleam@otp@actor:continue(
                update_threads(State@1, Threads, Next_thread_ids)
            )
    end.

-file("src/engine/dm_router.gleam", 299).
-spec result_to_option({ok, BKC} | {error, nil}) -> gleam@option:option(BKC).
result_to_option(Result) ->
    case Result of
        {ok, Value} ->
            {some, Value};

        {error, _} ->
            none
    end.

-file("src/engine/dm_router.gleam", 119).
-spec reply_to_thread(
    integer(),
    integer(),
    binary(),
    gleam@erlang@process:subject({ok, engine@types:direct_message()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
reply_to_thread(Thread, From, Body, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(2, State), Thread) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, {thread_store, Participants, Message_ids}} ->
            case gleam@set:contains(Participants, From) of
                false ->
                    gleam@erlang@process:send(Reply, {error, permission_denied}),
                    gleam@otp@actor:continue(State);

                true ->
                    In_reply_to = begin
                        _pipe = gleam@list:first(Message_ids),
                        result_to_option(_pipe)
                    end,
                    case other_participant(Participants, From) of
                        {error, Error} ->
                            gleam@erlang@process:send(Reply, {error, Error}),
                            gleam@otp@actor:continue(State);

                        {ok, To} ->
                            {Message, State@1} = create_message(
                                Thread,
                                In_reply_to,
                                From,
                                To,
                                Body,
                                State
                            ),
                            Threads = gleam@dict:insert(
                                erlang:element(2, State@1),
                                Thread,
                                {thread_store,
                                    Participants,
                                    [erlang:element(2, Message) | Message_ids]}
                            ),
                            gleam@erlang@process:send(Reply, {ok, Message}),
                            gleam@otp@actor:continue(
                                update_threads(
                                    State@1,
                                    Threads,
                                    erlang:element(5, State@1)
                                )
                            )
                    end
            end
    end.

-file("src/engine/dm_router.gleam", 78).
-spec handle_message(message(), state()) -> gleam@otp@actor:next(message(), state()).
handle_message(Message, State) ->
    case Message of
        {send_new, From, To, Body, Reply} ->
            send_new(From, To, Body, Reply, State);

        {reply, Thread, From@1, Body@1, Reply@1} ->
            reply_to_thread(Thread, From@1, Body@1, Reply@1, State);

        {list_inbox, User, Reply@2} ->
            list_inbox(User, Reply@2, State);

        {list_thread, Thread@1, Requester, Reply@3} ->
            list_thread(Thread@1, Requester, Reply@3, State);

        shutdown ->
            {stop, normal}
    end.

-file("src/engine/dm_router.gleam", 45).
-spec start_with(integer(), integer()) -> {ok,
        gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start_with(Thread_start, Message_start) ->
    gleam@otp@actor:start(
        {state,
            maps:new(),
            maps:new(),
            maps:new(),
            engine@ids:dm_thread_ids(Thread_start),
            engine@ids:message_ids(Message_start)},
        fun handle_message/2
    ).

-file("src/engine/dm_router.gleam", 41).
-spec start() -> {ok, gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start() ->
    start_with(1, 1).
