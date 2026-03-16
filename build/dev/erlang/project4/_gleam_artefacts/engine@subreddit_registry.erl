-module(engine@subreddit_registry).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/engine/subreddit_registry.gleam").
-export([start_with/2, start/1]).
-export_type([message/0, state/0, entry/0]).

-type message() :: {create,
        binary(),
        integer(),
        gleam@erlang@process:subject({ok, engine@types:subreddit()} |
            {error, engine@types:engine_error()})} |
    {join,
        integer(),
        integer(),
        gleam@erlang@process:subject({ok, engine@types:subreddit()} |
            {error, engine@types:engine_error()})} |
    {leave,
        integer(),
        integer(),
        gleam@erlang@process:subject({ok, engine@types:subreddit()} |
            {error, engine@types:engine_error()})} |
    {lookup_by_id,
        integer(),
        gleam@erlang@process:subject(gleam@option:option(engine@types:subreddit()))} |
    {lookup_by_name,
        binary(),
        gleam@erlang@process:subject(gleam@option:option(engine@types:subreddit()))} |
    {record_post,
        integer(),
        integer(),
        gleam@erlang@process:subject({ok, engine@types:subreddit()} |
            {error, engine@types:engine_error()})} |
    {remove_post,
        integer(),
        integer(),
        gleam@erlang@process:subject({ok, engine@types:subreddit()} |
            {error, engine@types:engine_error()})} |
    shutdown.

-type state() :: {state,
        gleam@dict:dict(integer(), entry()),
        gleam@dict:dict(binary(), integer()),
        engine@ids:id_generator(integer()),
        gleam@erlang@process:subject(engine@user_registry:message())}.

-type entry() :: {entry,
        gleam@erlang@process:subject(engine@subreddit:message())}.

-file("src/engine/subreddit_registry.gleam", 74).
-spec new_state(
    integer(),
    gleam@erlang@process:subject(engine@user_registry:message())
) -> state().
new_state(Start_id, User_registry) ->
    {state,
        maps:new(),
        maps:new(),
        engine@ids:subreddit_ids(Start_id),
        User_registry}.

-file("src/engine/subreddit_registry.gleam", 104).
-spec create_subreddit(
    binary(),
    integer(),
    gleam@erlang@process:subject({ok, engine@types:subreddit()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
create_subreddit(Name, Creator, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(3, State), Name) of
        {ok, _} ->
            gleam@erlang@process:send(Reply, {error, already_exists}),
            gleam@otp@actor:continue(State);

        {error, nil} ->
            {Subreddit_id, Next_ids} = engine@ids:next(erlang:element(4, State)),
            Members = gleam@set:insert(gleam@set:new(), Creator),
            Snapshot = {subreddit, Subreddit_id, Name, Members, []},
            case engine@subreddit:start(Snapshot) of
                {error, _} ->
                    gleam@erlang@process:send(Reply, {error, invalid_state}),
                    gleam@otp@actor:continue(State);

                {ok, Subject} ->
                    gleam@erlang@process:send(Reply, {ok, Snapshot}),
                    _ = gleam@erlang@process:call(
                        erlang:element(5, State),
                        fun(Responder) ->
                            {add_membership, Creator, Subreddit_id, Responder}
                        end,
                        5000
                    ),
                    Entry = {entry, Subject},
                    Subreddits = gleam@dict:insert(
                        erlang:element(2, State),
                        Subreddit_id,
                        Entry
                    ),
                    Names = gleam@dict:insert(
                        erlang:element(3, State),
                        Name,
                        Subreddit_id
                    ),
                    gleam@otp@actor:continue(
                        {state,
                            Subreddits,
                            Names,
                            Next_ids,
                            erlang:element(5, State)}
                    )
            end
    end.

-file("src/engine/subreddit_registry.gleam", 163).
-spec join_subreddit(
    integer(),
    integer(),
    gleam@erlang@process:subject({ok, engine@types:subreddit()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
join_subreddit(Subreddit_id, User, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(2, State), Subreddit_id) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, Entry} ->
            Result = gleam@erlang@process:call(
                erlang:element(2, Entry),
                fun(Responder) -> {add_member, User, Responder} end,
                5000
            ),
            case Result of
                {error, Engine_error} ->
                    gleam@erlang@process:send(Reply, {error, Engine_error}),
                    gleam@otp@actor:continue(State);

                {ok, Updated} ->
                    _ = gleam@erlang@process:call(
                        erlang:element(5, State),
                        fun(Responder@1) ->
                            {add_membership, User, Subreddit_id, Responder@1}
                        end,
                        5000
                    ),
                    gleam@erlang@process:send(Reply, {ok, Updated}),
                    gleam@otp@actor:continue(State)
            end
    end.

-file("src/engine/subreddit_registry.gleam", 210).
-spec leave_subreddit(
    integer(),
    integer(),
    gleam@erlang@process:subject({ok, engine@types:subreddit()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
leave_subreddit(Subreddit_id, User, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(2, State), Subreddit_id) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, Entry} ->
            Result = gleam@erlang@process:call(
                erlang:element(2, Entry),
                fun(Responder) -> {remove_member, User, Responder} end,
                5000
            ),
            case Result of
                {error, Engine_error} ->
                    gleam@erlang@process:send(Reply, {error, Engine_error}),
                    gleam@otp@actor:continue(State);

                {ok, Updated} ->
                    _ = gleam@erlang@process:call(
                        erlang:element(5, State),
                        fun(Responder@1) ->
                            {remove_membership, User, Subreddit_id, Responder@1}
                        end,
                        5000
                    ),
                    gleam@erlang@process:send(Reply, {ok, Updated}),
                    gleam@otp@actor:continue(State)
            end
    end.

-file("src/engine/subreddit_registry.gleam", 285).
-spec fetch_snapshot(entry()) -> engine@types:subreddit().
fetch_snapshot(Entry) ->
    gleam@erlang@process:call(
        erlang:element(2, Entry),
        fun(Field@0) -> {snapshot, Field@0} end,
        5000
    ).

-file("src/engine/subreddit_registry.gleam", 259).
-spec lookup_by_id(
    integer(),
    gleam@erlang@process:subject(gleam@option:option(engine@types:subreddit())),
    state()
) -> gleam@otp@actor:next(message(), state()).
lookup_by_id(Subreddit_id, Reply, State) ->
    Snapshot = begin
        _pipe = gleam_stdlib:map_get(erlang:element(2, State), Subreddit_id),
        _pipe@1 = gleam@option:from_result(_pipe),
        gleam@option:map(_pipe@1, fun(Entry) -> fetch_snapshot(Entry) end)
    end,
    gleam@erlang@process:send(Reply, Snapshot),
    gleam@otp@actor:continue(State).

-file("src/engine/subreddit_registry.gleam", 272).
-spec lookup_by_name(
    binary(),
    gleam@erlang@process:subject(gleam@option:option(engine@types:subreddit())),
    state()
) -> gleam@otp@actor:next(message(), state()).
lookup_by_name(Name, Reply, State) ->
    Subreddit = begin
        _pipe = gleam@option:from_result(
            gleam_stdlib:map_get(erlang:element(3, State), Name)
        ),
        _pipe@1 = gleam@option:then(
            _pipe,
            fun(Id) ->
                gleam@option:from_result(
                    gleam_stdlib:map_get(erlang:element(2, State), Id)
                )
            end
        ),
        gleam@option:map(_pipe@1, fun(Entry) -> fetch_snapshot(Entry) end)
    end,
    gleam@erlang@process:send(Reply, Subreddit),
    gleam@otp@actor:continue(State).

-file("src/engine/subreddit_registry.gleam", 289).
-spec record_post(
    integer(),
    integer(),
    gleam@erlang@process:subject({ok, engine@types:subreddit()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
record_post(Subreddit_id, Post, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(2, State), Subreddit_id) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, Entry} ->
            Updated = gleam@erlang@process:call(
                erlang:element(2, Entry),
                fun(Responder) -> {record_post, Post, Responder} end,
                5000
            ),
            gleam@erlang@process:send(Reply, {ok, Updated}),
            gleam@otp@actor:continue(State)
    end.

-file("src/engine/subreddit_registry.gleam", 316).
-spec remove_post(
    integer(),
    integer(),
    gleam@erlang@process:subject({ok, engine@types:subreddit()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
remove_post(Subreddit_id, Post, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(2, State), Subreddit_id) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, Entry} ->
            Updated = gleam@erlang@process:call(
                erlang:element(2, Entry),
                fun(Responder) -> {remove_post, Post, Responder} end,
                5000
            ),
            gleam@erlang@process:send(Reply, {ok, Updated}),
            gleam@otp@actor:continue(State)
    end.

-file("src/engine/subreddit_registry.gleam", 86).
-spec handle_message(message(), state()) -> gleam@otp@actor:next(message(), state()).
handle_message(Message, State) ->
    case Message of
        {create, Name, Creator, Reply} ->
            create_subreddit(Name, Creator, Reply, State);

        {join, Subreddit, User, Reply@1} ->
            join_subreddit(Subreddit, User, Reply@1, State);

        {leave, Subreddit@1, User@1, Reply@2} ->
            leave_subreddit(Subreddit@1, User@1, Reply@2, State);

        {lookup_by_id, Subreddit@2, Reply@3} ->
            lookup_by_id(Subreddit@2, Reply@3, State);

        {lookup_by_name, Name@1, Reply@4} ->
            lookup_by_name(Name@1, Reply@4, State);

        {record_post, Subreddit@3, Post, Reply@5} ->
            record_post(Subreddit@3, Post, Reply@5, State);

        {remove_post, Subreddit@4, Post@1, Reply@6} ->
            remove_post(Subreddit@4, Post@1, Reply@6, State);

        shutdown ->
            {stop, normal}
    end.

-file("src/engine/subreddit_registry.gleam", 54).
-spec start_with(
    integer(),
    gleam@erlang@process:subject(engine@user_registry:message())
) -> {ok, gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start_with(Start_id, User_registry) ->
    gleam@otp@actor:start(
        new_state(Start_id, User_registry),
        fun handle_message/2
    ).

-file("src/engine/subreddit_registry.gleam", 48).
-spec start(gleam@erlang@process:subject(engine@user_registry:message())) -> {ok,
        gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start(User_registry) ->
    start_with(1, User_registry).
