-module(sim@client).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/sim/client.gleam").
-export([start/5]).
-export_type([message/0, client_config/0, state/0]).

-type message() :: 'begin' | tick | shutdown.

-type client_config() :: {client_config, binary(), list(binary()), binary()}.

-type state() :: {state,
        integer(),
        binary(),
        engine@supervisor:services(),
        gleam@erlang@process:subject(sim@coordinator:message()),
        client_config(),
        gleam@option:option(engine@types:user()),
        gleam@dict:dict(binary(), integer()),
        list(integer()),
        integer()}.

-file("src/sim/client.gleam", 147).
-spec resolve_subreddit(binary(), engine@types:user(), state()) -> gleam@option:option(integer()).
resolve_subreddit(Name, User, State) ->
    Lookup = gleam@erlang@process:call(
        erlang:element(3, erlang:element(4, State)),
        fun(Responder) -> {lookup_by_name, Name, Responder} end,
        5000
    ),
    Maybe_existing = case Lookup of
        {some, Subreddit} ->
            {some, erlang:element(2, Subreddit)};

        none ->
            none
    end,
    case Maybe_existing of
        {some, Subreddit_id} ->
            {some, Subreddit_id};

        none ->
            Created = gleam@erlang@process:call(
                erlang:element(3, erlang:element(4, State)),
                fun(Responder@1) ->
                    {create, Name, erlang:element(2, User), Responder@1}
                end,
                5000
            ),
            case Created of
                {ok, Subreddit@1} ->
                    {some, erlang:element(2, Subreddit@1)};

                {error, _} ->
                    none
            end
    end.

-file("src/sim/client.gleam", 358).
-spec safe_mod(integer(), integer()) -> integer().
safe_mod(Value, Divisor) ->
    Positive_divisor = case Divisor of
        _ when Divisor < 0 ->
            - Divisor;

        _ ->
            Divisor
    end,
    case Positive_divisor of
        0 ->
            0;

        _ when Value < 0 ->
            safe_mod(Value + Positive_divisor, Positive_divisor);

        _ when Value >= Positive_divisor ->
            safe_mod(Value - Positive_divisor, Positive_divisor);

        _ ->
            Value
    end.

-file("src/sim/client.gleam", 340).
-spec pick_subreddit(state(), integer()) -> gleam@option:option(integer()).
pick_subreddit(State, Seed) ->
    Entries = maps:to_list(erlang:element(8, State)),
    case Entries of
        [] ->
            none;

        _ ->
            Index = safe_mod(Seed, erlang:length(Entries)),
            case gleam@list:drop(Entries, Index) of
                [{_, Subreddit_id} | _] ->
                    {some, Subreddit_id};

                _ ->
                    none
            end
    end.

-file("src/sim/client.gleam", 373).
-spec record_operation(state(), binary()) -> nil.
record_operation(State, Kind) ->
    gleam@erlang@process:send(
        erlang:element(5, State),
        {record_sample, erlang:element(3, State), {operation_recorded, Kind}}
    ).

-file("src/sim/client.gleam", 266).
-spec attempt_comment(state()) -> state().
attempt_comment(State) ->
    case erlang:element(7, State) of
        none ->
            State;

        {some, User} ->
            case erlang:element(9, State) of
                [] ->
                    State;

                [Post_id | _] ->
                    Result = gleam@erlang@process:call(
                        erlang:element(4, erlang:element(4, State)),
                        fun(Responder) ->
                            {create_comment,
                                erlang:element(2, User),
                                Post_id,
                                none,
                                erlang:list_to_binary(
                                    [<<"Re: post #"/utf8>>,
                                        erlang:integer_to_binary(Post_id),
                                        <<" from "/utf8>>,
                                        erlang:element(3, State)]
                                ),
                                Responder}
                        end,
                        5000
                    ),
                    case Result of
                        {ok, _} ->
                            record_operation(State, <<"comment_create"/utf8>>),
                            State;

                        {error, _} ->
                            State
                    end
            end
    end.

-file("src/sim/client.gleam", 306).
-spec attempt_vote(state()) -> state().
attempt_vote(State) ->
    case erlang:element(7, State) of
        none ->
            State;

        {some, User} ->
            case erlang:element(9, State) of
                [] ->
                    State;

                [Post_id | _] ->
                    Result = gleam@erlang@process:call(
                        erlang:element(4, erlang:element(4, State)),
                        fun(Responder) ->
                            {vote_on_post,
                                erlang:element(2, User),
                                Post_id,
                                upvote,
                                Responder}
                        end,
                        5000
                    ),
                    case Result of
                        {ok, _} ->
                            record_operation(State, <<"vote_up"/utf8>>),
                            State;

                        {error, _} ->
                            State
                    end
            end
    end.

-file("src/sim/client.gleam", 380).
-spec set_user(state(), gleam@option:option(engine@types:user())) -> state().
set_user(State, User) ->
    {state,
        erlang:element(2, State),
        erlang:element(3, State),
        erlang:element(4, State),
        erlang:element(5, State),
        erlang:element(6, State),
        User,
        erlang:element(8, State),
        erlang:element(9, State),
        erlang:element(10, State)}.

-file("src/sim/client.gleam", 75).
-spec ensure_user(state()) -> state().
ensure_user(State) ->
    case erlang:element(7, State) of
        {some, _} ->
            State;

        none ->
            Username = erlang:list_to_binary(
                [erlang:element(2, erlang:element(6, State)),
                    <<"-"/utf8>>,
                    erlang:integer_to_binary(erlang:element(2, State))]
            ),
            Result = gleam@erlang@process:call(
                erlang:element(2, erlang:element(4, State)),
                fun(Responder) -> {register, Username, Responder} end,
                5000
            ),
            case Result of
                {ok, User} ->
                    record_operation(State, <<"user_register"/utf8>>),
                    set_user(State, {some, User});

                {error, _} ->
                    State
            end
    end.

-file("src/sim/client.gleam", 191).
-spec refresh_user(state(), integer()) -> state().
refresh_user(State, User_id) ->
    Lookup = gleam@erlang@process:call(
        erlang:element(2, erlang:element(4, State)),
        fun(Responder) -> {lookup_by_id, User_id, Responder} end,
        5000
    ),
    case Lookup of
        {some, User} ->
            set_user(State, {some, User});

        none ->
            State
    end.

-file("src/sim/client.gleam", 394).
-spec set_subscriptions(state(), gleam@dict:dict(binary(), integer())) -> state().
set_subscriptions(State, Subscriptions) ->
    {state,
        erlang:element(2, State),
        erlang:element(3, State),
        erlang:element(4, State),
        erlang:element(5, State),
        erlang:element(6, State),
        erlang:element(7, State),
        Subscriptions,
        erlang:element(9, State),
        erlang:element(10, State)}.

-file("src/sim/client.gleam", 110).
-spec ensure_subscription(binary(), state()) -> state().
ensure_subscription(Name, State) ->
    case erlang:element(7, State) of
        none ->
            State;

        {some, User} ->
            case gleam_stdlib:map_get(erlang:element(8, State), Name) of
                {ok, _} ->
                    State;

                {error, nil} ->
                    case resolve_subreddit(Name, User, State) of
                        none ->
                            State;

                        {some, Subreddit_id} ->
                            Updated_subscriptions = gleam@dict:insert(
                                erlang:element(8, State),
                                Name,
                                Subreddit_id
                            ),
                            State_with_subscription = set_subscriptions(
                                State,
                                Updated_subscriptions
                            ),
                            _ = gleam@erlang@process:call(
                                erlang:element(3, erlang:element(4, State)),
                                fun(Responder) ->
                                    {join,
                                        Subreddit_id,
                                        erlang:element(2, User),
                                        Responder}
                                end,
                                5000
                            ),
                            Refreshed = refresh_user(
                                State_with_subscription,
                                erlang:element(2, User)
                            ),
                            record_operation(
                                Refreshed,
                                <<"subreddit_join"/utf8>>
                            ),
                            Refreshed
                    end
            end
    end.

-file("src/sim/client.gleam", 102).
-spec ensure_home_subreddits(state()) -> state().
ensure_home_subreddits(State) ->
    gleam@list:fold(
        erlang:element(3, erlang:element(6, State)),
        State,
        fun(State_acc, Name) -> ensure_subscription(Name, State_acc) end
    ).

-file("src/sim/client.gleam", 411).
-spec set_posts(state(), list(integer())) -> state().
set_posts(State, Posts) ->
    {state,
        erlang:element(2, State),
        erlang:element(3, State),
        erlang:element(4, State),
        erlang:element(5, State),
        erlang:element(6, State),
        erlang:element(7, State),
        erlang:element(8, State),
        Posts,
        erlang:element(10, State)}.

-file("src/sim/client.gleam", 223).
-spec attempt_post(state()) -> state().
attempt_post(State) ->
    case erlang:element(7, State) of
        none ->
            State;

        {some, User} ->
            case pick_subreddit(State, erlang:element(10, State)) of
                none ->
                    State;

                {some, Subreddit_id} ->
                    Body = erlang:list_to_binary(
                        [erlang:element(4, erlang:element(6, State)),
                            <<" #"/utf8>>,
                            erlang:integer_to_binary(erlang:element(10, State)),
                            <<" by "/utf8>>,
                            erlang:element(3, State)]
                    ),
                    Result = gleam@erlang@process:call(
                        erlang:element(4, erlang:element(4, State)),
                        fun(Responder) ->
                            {create_post,
                                erlang:element(2, User),
                                Subreddit_id,
                                Body,
                                Responder}
                        end,
                        5000
                    ),
                    case Result of
                        {ok, Post} ->
                            record_operation(State, <<"post_create"/utf8>>),
                            set_posts(
                                State,
                                [erlang:element(2, Post) |
                                    erlang:element(9, State)]
                            );

                        {error, _} ->
                            State
                    end
            end
    end.

-file("src/sim/client.gleam", 207).
-spec perform_action(state()) -> state().
perform_action(State) ->
    case erlang:element(7, State) of
        none ->
            State;

        {some, _} ->
            case erlang:length(maps:to_list(erlang:element(8, State))) of
                0 ->
                    State;

                _ ->
                    case safe_mod(erlang:element(10, State), 3) of
                        0 ->
                            attempt_post(State);

                        1 ->
                            attempt_comment(State);

                        _ ->
                            attempt_vote(State)
                    end
            end
    end.

-file("src/sim/client.gleam", 425).
-spec set_tick(state(), integer()) -> state().
set_tick(State, Tick) ->
    {state,
        erlang:element(2, State),
        erlang:element(3, State),
        erlang:element(4, State),
        erlang:element(5, State),
        erlang:element(6, State),
        erlang:element(7, State),
        erlang:element(8, State),
        erlang:element(9, State),
        Tick}.

-file("src/sim/client.gleam", 354).
-spec increment_tick(state()) -> state().
increment_tick(State) ->
    set_tick(State, erlang:element(10, State) + 1).

-file("src/sim/client.gleam", 67).
-spec handle_message(message(), state()) -> gleam@otp@actor:next(message(), state()).
handle_message(Message, State) ->
    case Message of
        'begin' ->
            gleam@otp@actor:continue(
                begin
                    _pipe = State,
                    _pipe@1 = ensure_user(_pipe),
                    ensure_home_subreddits(_pipe@1)
                end
            );

        tick ->
            gleam@otp@actor:continue(
                begin
                    _pipe@2 = State,
                    _pipe@3 = ensure_user(_pipe@2),
                    _pipe@4 = ensure_home_subreddits(_pipe@3),
                    _pipe@5 = perform_action(_pipe@4),
                    increment_tick(_pipe@5)
                end
            );

        shutdown ->
            {stop, normal}
    end.

-file("src/sim/client.gleam", 30).
-spec start(
    integer(),
    binary(),
    engine@supervisor:services(),
    gleam@erlang@process:subject(sim@coordinator:message()),
    client_config()
) -> {ok, gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start(Id, Label, Engine_services, Coordinator_subject, Config) ->
    gleam@otp@actor:start(
        {state,
            Id,
            Label,
            Engine_services,
            Coordinator_subject,
            Config,
            none,
            maps:new(),
            [],
            0},
        fun handle_message/2
    ).
