-module(engine@subreddit).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/engine/subreddit.gleam").
-export([start/1]).
-export_type([message/0, state/0]).

-type message() :: {snapshot,
        gleam@erlang@process:subject(engine@types:subreddit())} |
    {add_member,
        integer(),
        gleam@erlang@process:subject({ok, engine@types:subreddit()} |
            {error, engine@types:engine_error()})} |
    {remove_member,
        integer(),
        gleam@erlang@process:subject({ok, engine@types:subreddit()} |
            {error, engine@types:engine_error()})} |
    {record_post,
        integer(),
        gleam@erlang@process:subject(engine@types:subreddit())} |
    {remove_post,
        integer(),
        gleam@erlang@process:subject(engine@types:subreddit())} |
    {list_posts, gleam@erlang@process:subject(list(integer()))} |
    shutdown.

-type state() :: {state, engine@types:subreddit()}.

-file("src/engine/subreddit.gleam", 53).
-spec add_member(
    integer(),
    gleam@erlang@process:subject({ok, engine@types:subreddit()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
add_member(User, Reply, State) ->
    Info = erlang:element(2, State),
    case gleam@set:contains(erlang:element(4, Info), User) of
        true ->
            gleam@erlang@process:send(Reply, {ok, Info}),
            gleam@otp@actor:continue(State);

        false ->
            Members = gleam@set:insert(erlang:element(4, Info), User),
            Updated = {subreddit,
                erlang:element(2, Info),
                erlang:element(3, Info),
                Members,
                erlang:element(5, Info)},
            gleam@erlang@process:send(Reply, {ok, Updated}),
            gleam@otp@actor:continue({state, Updated})
    end.

-file("src/engine/subreddit.gleam", 81).
-spec remove_member(
    integer(),
    gleam@erlang@process:subject({ok, engine@types:subreddit()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
remove_member(User, Reply, State) ->
    Info = erlang:element(2, State),
    case gleam@set:contains(erlang:element(4, Info), User) of
        false ->
            gleam@erlang@process:send(Reply, {error, invalid_state}),
            gleam@otp@actor:continue(State);

        true ->
            Members = gleam@set:delete(erlang:element(4, Info), User),
            Updated = {subreddit,
                erlang:element(2, Info),
                erlang:element(3, Info),
                Members,
                erlang:element(5, Info)},
            gleam@erlang@process:send(Reply, {ok, Updated}),
            gleam@otp@actor:continue({state, Updated})
    end.

-file("src/engine/subreddit.gleam", 109).
-spec record_post(
    integer(),
    gleam@erlang@process:subject(engine@types:subreddit()),
    state()
) -> gleam@otp@actor:next(message(), state()).
record_post(Post, Reply, State) ->
    Info = erlang:element(2, State),
    Already_indexed = gleam@list:contains(erlang:element(5, Info), Post),
    Posts = case Already_indexed of
        true ->
            erlang:element(5, Info);

        false ->
            [Post | erlang:element(5, Info)]
    end,
    Updated = {subreddit,
        erlang:element(2, Info),
        erlang:element(3, Info),
        erlang:element(4, Info),
        Posts},
    gleam@erlang@process:send(Reply, Updated),
    gleam@otp@actor:continue({state, Updated}).

-file("src/engine/subreddit.gleam", 131).
-spec remove_post(
    integer(),
    gleam@erlang@process:subject(engine@types:subreddit()),
    state()
) -> gleam@otp@actor:next(message(), state()).
remove_post(Target, Reply, State) ->
    Pruned = gleam@list:filter(
        erlang:element(5, erlang:element(2, State)),
        fun(Post) -> Post /= Target end
    ),
    Updated = {subreddit,
        erlang:element(2, erlang:element(2, State)),
        erlang:element(3, erlang:element(2, State)),
        erlang:element(4, erlang:element(2, State)),
        Pruned},
    gleam@erlang@process:send(Reply, Updated),
    gleam@otp@actor:continue({state, Updated}).

-file("src/engine/subreddit.gleam", 34).
-spec handle_message(message(), state()) -> gleam@otp@actor:next(message(), state()).
handle_message(Message, State) ->
    case Message of
        {snapshot, Reply} ->
            gleam@erlang@process:send(Reply, erlang:element(2, State)),
            gleam@otp@actor:continue(State);

        {add_member, User, Reply@1} ->
            add_member(User, Reply@1, State);

        {remove_member, User@1, Reply@2} ->
            remove_member(User@1, Reply@2, State);

        {record_post, Post, Reply@3} ->
            record_post(Post, Reply@3, State);

        {remove_post, Post@1, Reply@4} ->
            remove_post(Post@1, Reply@4, State);

        {list_posts, Reply@5} ->
            gleam@erlang@process:send(
                Reply@5,
                erlang:element(5, erlang:element(2, State))
            ),
            gleam@otp@actor:continue(State);

        shutdown ->
            {stop, normal}
    end.

-file("src/engine/subreddit.gleam", 26).
-spec start(engine@types:subreddit()) -> {ok,
        gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start(Initial) ->
    gleam@otp@actor:start({state, Initial}, fun handle_message/2).
