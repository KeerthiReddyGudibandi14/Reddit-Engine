-module(engine@content_coordinator).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/engine/content_coordinator.gleam").
-export([start_with/4, start/2]).
-export_type([message/0, post_record/0, comment_record/0, state/0]).

-type message() :: {create_post,
        integer(),
        integer(),
        binary(),
        gleam@erlang@process:subject({ok, engine@types:post()} |
            {error, engine@types:engine_error()})} |
    {create_comment,
        integer(),
        integer(),
        gleam@option:option(integer()),
        binary(),
        gleam@erlang@process:subject({ok, engine@types:comment()} |
            {error, engine@types:engine_error()})} |
    {vote_on_post,
        integer(),
        integer(),
        engine@types:vote(),
        gleam@erlang@process:subject({ok, engine@types:post()} |
            {error, engine@types:engine_error()})} |
    {vote_on_comment,
        integer(),
        integer(),
        engine@types:vote(),
        gleam@erlang@process:subject({ok, engine@types:comment()} |
            {error, engine@types:engine_error()})} |
    {fetch_post,
        integer(),
        gleam@erlang@process:subject(gleam@option:option(engine@types:post()))} |
    {fetch_comments,
        integer(),
        gleam@erlang@process:subject(list(engine@types:comment()))} |
    {list_posts_by_subreddits,
        list(integer()),
        integer(),
        gleam@erlang@process:subject(list(engine@types:post()))} |
    shutdown.

-type post_record() :: {post_record,
        engine@types:post(),
        gleam@dict:dict(integer(), engine@types:vote())}.

-type comment_record() :: {comment_record,
        engine@types:comment(),
        gleam@dict:dict(integer(), engine@types:vote())}.

-type state() :: {state,
        gleam@dict:dict(integer(), post_record()),
        gleam@dict:dict(integer(), comment_record()),
        engine@ids:id_generator(integer()),
        engine@ids:id_generator(integer()),
        gleam@erlang@process:subject(engine@user_registry:message()),
        gleam@erlang@process:subject(engine@subreddit_registry:message())}.

-file("src/engine/content_coordinator.gleam", 118).
-spec timestamp() -> integer().
timestamp() ->
    os:system_time(millisecond).

-file("src/engine/content_coordinator.gleam", 122).
-spec vote_value(engine@types:vote()) -> integer().
vote_value(Vote) ->
    case Vote of
        upvote ->
            1;

        downvote ->
            -1
    end.

-file("src/engine/content_coordinator.gleam", 362).
-spec fetch_post(
    integer(),
    gleam@erlang@process:subject(gleam@option:option(engine@types:post())),
    state()
) -> gleam@otp@actor:next(message(), state()).
fetch_post(Post_id, Reply, State) ->
    Post = begin
        _pipe = gleam_stdlib:map_get(erlang:element(2, State), Post_id),
        _pipe@1 = gleam@option:from_result(_pipe),
        gleam@option:map(_pipe@1, fun(Record) -> erlang:element(2, Record) end)
    end,
    gleam@erlang@process:send(Reply, Post),
    gleam@otp@actor:continue(State).

-file("src/engine/content_coordinator.gleam", 375).
-spec fetch_comments(
    integer(),
    gleam@erlang@process:subject(list(engine@types:comment())),
    state()
) -> gleam@otp@actor:next(message(), state()).
fetch_comments(Post_id, Reply, State) ->
    Comments = begin
        _pipe = erlang:element(3, State),
        _pipe@1 = maps:values(_pipe),
        _pipe@2 = gleam@list:filter(
            _pipe@1,
            fun(Record) ->
                erlang:element(3, erlang:element(2, Record)) =:= Post_id
            end
        ),
        _pipe@3 = gleam@list:map(
            _pipe@2,
            fun(Record@1) -> erlang:element(2, Record@1) end
        ),
        gleam@list:sort(
            _pipe@3,
            fun(A, B) ->
                case gleam@int:compare(
                    erlang:element(7, A),
                    erlang:element(7, B)
                ) of
                    lt ->
                        lt;

                    eq ->
                        gleam@int:compare(
                            erlang:element(2, A),
                            erlang:element(2, B)
                        );

                    gt ->
                        gt
                end
            end
        )
    end,
    gleam@erlang@process:send(Reply, Comments),
    gleam@otp@actor:continue(State).

-file("src/engine/content_coordinator.gleam", 396).
-spec list_posts_by_subreddits(
    list(integer()),
    integer(),
    gleam@erlang@process:subject(list(engine@types:post())),
    state()
) -> gleam@otp@actor:next(message(), state()).
list_posts_by_subreddits(Subreddit_ids, Limit, Reply, State) ->
    Targets = gleam@set:from_list(Subreddit_ids),
    Posts = begin
        _pipe = erlang:element(2, State),
        _pipe@1 = maps:values(_pipe),
        _pipe@2 = gleam@list:map(
            _pipe@1,
            fun(Record) -> erlang:element(2, Record) end
        ),
        _pipe@3 = gleam@list:filter(
            _pipe@2,
            fun(Post) ->
                gleam@set:contains(Targets, erlang:element(3, Post))
            end
        ),
        gleam@list:sort(
            _pipe@3,
            fun(A, B) ->
                case gleam@int:compare(
                    erlang:element(6, A),
                    erlang:element(6, B)
                ) of
                    lt ->
                        gt;

                    eq ->
                        gleam@int:compare(
                            erlang:element(7, B),
                            erlang:element(7, A)
                        );

                    gt ->
                        lt
                end
            end
        )
    end,
    Limited = gleam@list:take(Posts, gleam@int:max(Limit, 0)),
    gleam@erlang@process:send(Reply, Limited),
    gleam@otp@actor:continue(State).

-file("src/engine/content_coordinator.gleam", 420).
-spec ensure_membership(integer(), integer(), state()) -> {ok, integer()} |
    {error, engine@types:engine_error()}.
ensure_membership(User_id, Subreddit_id, State) ->
    User_option = gleam@erlang@process:call(
        erlang:element(6, State),
        fun(Responder) -> {lookup_by_id, User_id, Responder} end,
        5000
    ),
    case User_option of
        {some, User} ->
            case gleam@set:contains(erlang:element(4, User), Subreddit_id) of
                true ->
                    {ok, User_id};

                false ->
                    {error, permission_denied}
            end;

        none ->
            {error, not_found}
    end.

-file("src/engine/content_coordinator.gleam", 444).
-spec ensure_subreddit_exists(integer(), state()) -> {ok, integer()} |
    {error, engine@types:engine_error()}.
ensure_subreddit_exists(Subreddit_id, State) ->
    Subreddit_option = gleam@erlang@process:call(
        erlang:element(7, State),
        fun(Responder) -> {lookup_by_id, Subreddit_id, Responder} end,
        5000
    ),
    case Subreddit_option of
        {some, _} ->
            {ok, Subreddit_id};

        none ->
            {error, not_found}
    end.

-file("src/engine/content_coordinator.gleam", 129).
-spec create_post(
    integer(),
    integer(),
    binary(),
    gleam@erlang@process:subject({ok, engine@types:post()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
create_post(Author, Subreddit_id, Body, Reply, State) ->
    case ensure_membership(Author, Subreddit_id, State) of
        {error, Error} ->
            gleam@erlang@process:send(Reply, {error, Error}),
            gleam@otp@actor:continue(State);

        {ok, _} ->
            Exists = ensure_subreddit_exists(Subreddit_id, State),
            case Exists of
                {error, Error@1} ->
                    gleam@erlang@process:send(Reply, {error, Error@1}),
                    gleam@otp@actor:continue(State);

                {ok, _} ->
                    {Post_id, Next_post_ids} = engine@ids:next(
                        erlang:element(4, State)
                    ),
                    Created_at = timestamp(),
                    Post = {post,
                        Post_id,
                        Subreddit_id,
                        Author,
                        Body,
                        Created_at,
                        0},
                    Record = {post_record, Post, maps:new()},
                    Posts = gleam@dict:insert(
                        erlang:element(2, State),
                        Post_id,
                        Record
                    ),
                    Registry_result = gleam@erlang@process:call(
                        erlang:element(7, State),
                        fun(Responder) ->
                            {record_post, Subreddit_id, Post_id, Responder}
                        end,
                        5000
                    ),
                    case Registry_result of
                        {error, Error@2} ->
                            gleam@erlang@process:send(Reply, {error, Error@2}),
                            gleam@otp@actor:continue(State);

                        {ok, _} ->
                            gleam@erlang@process:send(Reply, {ok, Post}),
                            gleam@otp@actor:continue(
                                {state,
                                    Posts,
                                    erlang:element(3, State),
                                    Next_post_ids,
                                    erlang:element(5, State),
                                    erlang:element(6, State),
                                    erlang:element(7, State)}
                            )
                    end
            end
    end.

-file("src/engine/content_coordinator.gleam", 466).
-spec validate_parent(gleam@option:option(integer()), integer(), state()) -> {ok,
        nil} |
    {error, engine@types:engine_error()}.
validate_parent(Parent, Post_id, State) ->
    case Parent of
        none ->
            {ok, nil};

        {some, Comment_id} ->
            case gleam_stdlib:map_get(erlang:element(3, State), Comment_id) of
                {ok, {comment_record, Comment, _}} ->
                    case erlang:element(3, Comment) =:= Post_id of
                        true ->
                            {ok, nil};

                        false ->
                            {error, invalid_state}
                    end;

                _ ->
                    {error, invalid_state}
            end
    end.

-file("src/engine/content_coordinator.gleam", 202).
-spec create_comment(
    integer(),
    integer(),
    gleam@option:option(integer()),
    binary(),
    gleam@erlang@process:subject({ok, engine@types:comment()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
create_comment(Author, Post_id, Parent, Body, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(2, State), Post_id) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, {post_record, Post, _}} ->
            case ensure_membership(Author, erlang:element(3, Post), State) of
                {error, Error} ->
                    gleam@erlang@process:send(Reply, {error, Error}),
                    gleam@otp@actor:continue(State);

                {ok, _} ->
                    case validate_parent(Parent, Post_id, State) of
                        {error, Error@1} ->
                            gleam@erlang@process:send(Reply, {error, Error@1}),
                            gleam@otp@actor:continue(State);

                        {ok, _} ->
                            {Comment_id, Next_comment_ids} = engine@ids:next(
                                erlang:element(5, State)
                            ),
                            Created_at = timestamp(),
                            Comment = {comment,
                                Comment_id,
                                Post_id,
                                Parent,
                                Author,
                                Body,
                                Created_at,
                                0},
                            Record = {comment_record, Comment, maps:new()},
                            Comments = gleam@dict:insert(
                                erlang:element(3, State),
                                Comment_id,
                                Record
                            ),
                            gleam@erlang@process:send(Reply, {ok, Comment}),
                            gleam@otp@actor:continue(
                                {state,
                                    erlang:element(2, State),
                                    Comments,
                                    erlang:element(4, State),
                                    Next_comment_ids,
                                    erlang:element(6, State),
                                    erlang:element(7, State)}
                            )
                    end
            end
    end.

-file("src/engine/content_coordinator.gleam", 485).
-spec apply_vote(
    gleam@dict:dict(integer(), engine@types:vote()),
    integer(),
    engine@types:vote()
) -> {gleam@dict:dict(integer(), engine@types:vote()), integer()}.
apply_vote(Votes, Voter, Vote) ->
    case gleam_stdlib:map_get(Votes, Voter) of
        {error, nil} ->
            {gleam@dict:insert(Votes, Voter, Vote), vote_value(Vote)};

        {ok, Existing} ->
            case Existing =:= Vote of
                true ->
                    {gleam@dict:delete(Votes, Voter), - vote_value(Existing)};

                false ->
                    {gleam@dict:insert(Votes, Voter, Vote),
                        vote_value(Vote) - vote_value(Existing)}
            end
    end.

-file("src/engine/content_coordinator.gleam", 501).
-spec adjust_karma(integer(), integer(), state()) -> nil.
adjust_karma(Author, Delta, State) ->
    _ = gleam@erlang@process:call(
        erlang:element(6, State),
        fun(Responder) -> {adjust_karma, Author, Delta, Responder} end,
        5000
    ),
    nil.

-file("src/engine/content_coordinator.gleam", 262).
-spec vote_on_post(
    integer(),
    integer(),
    engine@types:vote(),
    gleam@erlang@process:subject({ok, engine@types:post()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
vote_on_post(Voter, Post_id, Vote, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(2, State), Post_id) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, Record} ->
            {Votes, Delta} = apply_vote(erlang:element(3, Record), Voter, Vote),
            Post = erlang:element(2, Record),
            case Delta of
                0 ->
                    gleam@erlang@process:send(Reply, {ok, Post}),
                    gleam@otp@actor:continue(State);

                _ ->
                    Updated = {post,
                        erlang:element(2, Post),
                        erlang:element(3, Post),
                        erlang:element(4, Post),
                        erlang:element(5, Post),
                        erlang:element(6, Post),
                        erlang:element(7, Post) + Delta},
                    Posts = gleam@dict:insert(
                        erlang:element(2, State),
                        Post_id,
                        {post_record, Updated, Votes}
                    ),
                    adjust_karma(erlang:element(4, Post), Delta, State),
                    gleam@erlang@process:send(Reply, {ok, Updated}),
                    gleam@otp@actor:continue(
                        {state,
                            Posts,
                            erlang:element(3, State),
                            erlang:element(4, State),
                            erlang:element(5, State),
                            erlang:element(6, State),
                            erlang:element(7, State)}
                    )
            end
    end.

-file("src/engine/content_coordinator.gleam", 311).
-spec vote_on_comment(
    integer(),
    integer(),
    engine@types:vote(),
    gleam@erlang@process:subject({ok, engine@types:comment()} |
        {error, engine@types:engine_error()}),
    state()
) -> gleam@otp@actor:next(message(), state()).
vote_on_comment(Voter, Comment_id, Vote, Reply, State) ->
    case gleam_stdlib:map_get(erlang:element(3, State), Comment_id) of
        {error, nil} ->
            gleam@erlang@process:send(Reply, {error, not_found}),
            gleam@otp@actor:continue(State);

        {ok, Record} ->
            {Votes, Delta} = apply_vote(erlang:element(3, Record), Voter, Vote),
            Comment = erlang:element(2, Record),
            case Delta of
                0 ->
                    gleam@erlang@process:send(Reply, {ok, Comment}),
                    gleam@otp@actor:continue(State);

                _ ->
                    Updated = {comment,
                        erlang:element(2, Comment),
                        erlang:element(3, Comment),
                        erlang:element(4, Comment),
                        erlang:element(5, Comment),
                        erlang:element(6, Comment),
                        erlang:element(7, Comment),
                        erlang:element(8, Comment) + Delta},
                    Comments = gleam@dict:insert(
                        erlang:element(3, State),
                        Comment_id,
                        {comment_record, Updated, Votes}
                    ),
                    adjust_karma(erlang:element(5, Comment), Delta, State),
                    gleam@erlang@process:send(Reply, {ok, Updated}),
                    gleam@otp@actor:continue(
                        {state,
                            erlang:element(2, State),
                            Comments,
                            erlang:element(4, State),
                            erlang:element(5, State),
                            erlang:element(6, State),
                            erlang:element(7, State)}
                    )
            end
    end.

-file("src/engine/content_coordinator.gleam", 100).
-spec handle_message(message(), state()) -> gleam@otp@actor:next(message(), state()).
handle_message(Message, State) ->
    case Message of
        {create_post, Author, Subreddit, Body, Reply} ->
            create_post(Author, Subreddit, Body, Reply, State);

        {create_comment, Author@1, Post, Parent, Body@1, Reply@1} ->
            create_comment(Author@1, Post, Parent, Body@1, Reply@1, State);

        {vote_on_post, Voter, Post@1, Vote, Reply@2} ->
            vote_on_post(Voter, Post@1, Vote, Reply@2, State);

        {vote_on_comment, Voter@1, Comment, Vote@1, Reply@3} ->
            vote_on_comment(Voter@1, Comment, Vote@1, Reply@3, State);

        {fetch_post, Post@2, Reply@4} ->
            fetch_post(Post@2, Reply@4, State);

        {fetch_comments, Post@3, Reply@5} ->
            fetch_comments(Post@3, Reply@5, State);

        {list_posts_by_subreddits, Subreddits, Limit, Reply@6} ->
            list_posts_by_subreddits(Subreddits, Limit, Reply@6, State);

        shutdown ->
            {stop, normal}
    end.

-file("src/engine/content_coordinator.gleam", 62).
-spec start_with(
    integer(),
    integer(),
    gleam@erlang@process:subject(engine@user_registry:message()),
    gleam@erlang@process:subject(engine@subreddit_registry:message())
) -> {ok, gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start_with(Post_start, Comment_start, User_registry, Subreddit_registry) ->
    gleam@otp@actor:start(
        {state,
            maps:new(),
            maps:new(),
            engine@ids:post_ids(Post_start),
            engine@ids:comment_ids(Comment_start),
            User_registry,
            Subreddit_registry},
        fun handle_message/2
    ).

-file("src/engine/content_coordinator.gleam", 55).
-spec start(
    gleam@erlang@process:subject(engine@user_registry:message()),
    gleam@erlang@process:subject(engine@subreddit_registry:message())
) -> {ok, gleam@erlang@process:subject(message())} |
    {error, gleam@otp@actor:start_error()}.
start(User_registry, Subreddit_registry) ->
    start_with(1, 1, User_registry, Subreddit_registry).
