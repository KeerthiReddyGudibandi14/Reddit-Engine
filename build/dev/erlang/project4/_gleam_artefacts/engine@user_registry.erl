-module(engine@user_registry).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/engine/user_registry.gleam").
-export([start_with/1, start/0]).
-export_type([message/0, state/0]).

-type message() :: {register,
        binary(),
        gleam@erlang@process:subject({ok, engine@types:user()} |
            {error, engine@types:engine_error()})} |
    {lookup_by_id,
        integer(),
        gleam@erlang@process:subject(gleam@option:option(engine@types:user()))} |
    {lookup_by_name,
        binary(),
        gleam@erlang@process:subject(gleam@option:option(engine@types:user()))} |
    {adjust_karma,
        integer(),
        integer(),
        gleam@erlang@process:subject({ok, engine@types:user()} |
            {error, engine@types:engine_error()})} |
    {add_membership,
        integer(),
        integer(),
        gleam@erlang@process:subject({ok, engine@types:user()} |
            {error, engine@types:engine_error()})} |
    {remove_membership,
        integer(),
        integer(),
        gleam@erlang@process:subject({ok, engine@types:user()} |
            {error, engine@types:engine_error()})} |
    shutdown.

-type state() :: {state,
        gleam@dict:dict(integer(), engine@types:user()),
        gleam@dict:dict(binary(), integer()),
        engine@ids:id_generator(integer())}.

-file("src/engine/user_registry.gleam", 54).
-spec new_state(integer()) -> state().
new_state(Start_id) ->
    {state, maps:new(), maps:new(), engine@ids:user_ids(Start_id)}.

-file("src/engine/user_registry.gleam", 72).
-spec register(
    binary(),
    gleam@erlang@process:subject({ok, engine@types:user()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
register(Name, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(3, State), Name) of
        {ok, _} ->
            gleam@erlang@process:send(Reply, {error, already_exists}),
            gleam@otp@actor:continue(State);

        {error, nil} ->
            {User_id, Next_ids} = engine@ids:next(erlang:element(4, State)),
            User = {user, User_id, Name, gleam@set:new(), 0},
            Users = gleam@dict:insert(erlang:element(2, State), User_id, User),
            Names = gleam@dict:insert(erlang:element(3, State), Name, User_id),
            gleam@erlang@process:send(Reply, {ok, User}),
            gleam@otp@actor:continue({state, Users, Names, Next_ids})
    end.

-file("src/engine/user_registry.gleam", 100).
-spec add_membership(
    integer(),
    integer(),
    gleam@erlang@process:subject({ok, engine@types:user()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
add_membership(User, Subreddit, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(2, State), User) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, Profile} ->
            Already_joined = gleam@set:contains(
                erlang:element(4, Profile),
                Subreddit
            ),
            Joined = case Already_joined of
                true ->
                    erlang:element(4, Profile);

                false ->
                    gleam@set:insert(erlang:element(4, Profile), Subreddit)
            end,
            Updated = {user,
                erlang:element(2, Profile),
                erlang:element(3, Profile),
                Joined,
                erlang:element(5, Profile)},
            Users = gleam@dict:insert(erlang:element(2, State), User, Updated),
            gleam@erlang@process:send(Reply, {ok, Updated}),
            gleam@otp@actor:continue(
                {state,
                    Users,
                    erlang:element(3, State),
                    erlang:element(4, State)}
            )
    end.

-file("src/engine/user_registry.gleam", 132).
-spec remove_membership(
    integer(),
    integer(),
    gleam@erlang@process:subject({ok, engine@types:user()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
remove_membership(User, Subreddit, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(2, State), User) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, Profile} ->
            case gleam@set:contains(erlang:element(4, Profile), Subreddit) of
                false ->
                    gleam@erlang@process:send(Reply, {error, invalid_state}),
                    gleam@otp@actor:continue(State);

                true ->
                    Joined = gleam@set:delete(
                        erlang:element(4, Profile),
                        Subreddit
                    ),
                    Updated = {user,
                        erlang:element(2, Profile),
                        erlang:element(3, Profile),
                        Joined,
                        erlang:element(5, Profile)},
                    Users = gleam@dict:insert(
                        erlang:element(2, State),
                        User,
                        Updated
                    ),
                    gleam@erlang@process:send(Reply, {ok, Updated}),
                    gleam@otp@actor:continue(
                        {state,
                            Users,
                            erlang:element(3, State),
                            erlang:element(4, State)}
                    )
            end
    end.

-file("src/engine/user_registry.gleam", 169).
-spec lookup_by_id(
    integer(),
    gleam@erlang@process:subject(gleam@option:option(engine@types:user())),
    state()
) -> gleam@otp@actor:next(message(), state()).
lookup_by_id(Id, Reply, State) ->
    gleam@erlang@process:send(
        Reply,
        gleam@option:from_result(
            gleam_stdlib:map_get(erlang:element(2, State), Id)
        )
    ),
    gleam@otp@actor:continue(State).

-file("src/engine/user_registry.gleam", 178).
-spec lookup_by_name(
    binary(),
    gleam@erlang@process:subject(gleam@option:option(engine@types:user())),
    state()
) -> gleam@otp@actor:next(message(), state()).
lookup_by_name(Name, Reply, State) ->
    User = begin
        _pipe = gleam@option:from_result(
            gleam_stdlib:map_get(erlang:element(3, State), Name)
        ),
        gleam@option:then(
            _pipe,
            fun(User_id) ->
                gleam@option:from_result(
                    gleam_stdlib:map_get(erlang:element(2, State), User_id)
                )
            end
        )
    end,
    gleam@erlang@process:send(Reply, User),
    gleam@otp@actor:continue(State).

-file("src/engine/user_registry.gleam", 192).
-spec adjust_karma(
    integer(),
    integer(),
    gleam@erlang@process:subject({ok, engine@types:user()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
adjust_karma(Id, Delta, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(2, State), Id) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, User} ->
            Updated = {user,
                erlang:element(2, User),
                erlang:element(3, User),
                erlang:element(4, User),
                erlang:element(5, User) + Delta},
            Users = gleam@dict:insert(erlang:element(2, State), Id, Updated),
            gleam@erlang@process:send(Reply, {ok, Updated}),
            gleam@otp@actor:continue(
                {state,
                    Users,
                    erlang:element(3, State),
                    erlang:element(4, State)}
            )
    end.

-file("src/engine/user_registry.gleam", 58).
-spec handle_message(message(), state()) -> gleam@otp@actor:next(message(), state()).
handle_message(Message, State) ->
    case Message of
        {register, Name, Reply} ->
            register(Name, Reply, State);

        {lookup_by_id, Id, Reply@1} ->
            lookup_by_id(Id, Reply@1, State);

        {lookup_by_name, Name@1, Reply@2} ->
            lookup_by_name(Name@1, Reply@2, State);

        {adjust_karma, Id@1, Delta, Reply@3} ->
            adjust_karma(Id@1, Delta, Reply@3, State);

        {add_membership, User, Subreddit, Reply@4} ->
            add_membership(User, Subreddit, Reply@4, State);

        {remove_membership, User@1, Subreddit@1, Reply@5} ->
            remove_membership(User@1, Subreddit@1, Reply@5, State);

        shutdown ->
            {stop, normal}
    end.

-file("src/engine/user_registry.gleam", 42).
-spec start_with(integer()) -> {ok, gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start_with(Start_id) ->
    gleam@otp@actor:start(new_state(Start_id), fun handle_message/2).

-file("src/engine/user_registry.gleam", 38).
-spec start() -> {ok, gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start() ->
    start_with(1).
