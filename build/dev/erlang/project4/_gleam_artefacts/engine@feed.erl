-module(engine@feed).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/engine/feed.gleam").
-export([truncate/2, sort_posts/2, fetch_feed/4]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-file("src/engine/feed.gleam", 22).
-spec truncate(list(engine@types:post()), integer()) -> list(engine@types:post()).
truncate(Posts, Count) ->
    gleam@list:take(Posts, Count).

-file("src/engine/feed.gleam", 81).
-spec rising_metric(engine@types:post(), integer()) -> float().
rising_metric(Post, Now) ->
    Age = gleam@int:max(Now - erlang:element(6, Post), 1),
    case erlang:float(Age) of
        +0.0 -> +0.0;
        -0.0 -> -0.0;
        Gleam@denominator -> erlang:float(erlang:element(7, Post)) / Gleam@denominator
    end.

-file("src/engine/feed.gleam", 86).
-spec compare_int_desc(integer(), integer()) -> gleam@order:order().
compare_int_desc(A, B) ->
    case gleam@int:compare(A, B) of
        lt ->
            gt;

        eq ->
            eq;

        gt ->
            lt
    end.

-file("src/engine/feed.gleam", 51).
-spec sort_hot(list(engine@types:post())) -> list(engine@types:post()).
sort_hot(Posts) ->
    gleam@list:sort(
        Posts,
        fun(Post_a, Post_b) ->
            case compare_int_desc(
                erlang:element(7, Post_a),
                erlang:element(7, Post_b)
            ) of
                eq ->
                    compare_int_desc(
                        erlang:element(6, Post_a),
                        erlang:element(6, Post_b)
                    );

                Other ->
                    Other
            end
        end
    ).

-file("src/engine/feed.gleam", 60).
-spec sort_new(list(engine@types:post())) -> list(engine@types:post()).
sort_new(Posts) ->
    gleam@list:sort(
        Posts,
        fun(Post_a, Post_b) ->
            case compare_int_desc(
                erlang:element(6, Post_a),
                erlang:element(6, Post_b)
            ) of
                eq ->
                    compare_int_desc(
                        erlang:element(2, Post_a),
                        erlang:element(2, Post_b)
                    );

                Other ->
                    Other
            end
        end
    ).

-file("src/engine/feed.gleam", 94).
-spec compare_float_desc(float(), float()) -> gleam@order:order().
compare_float_desc(A, B) ->
    case gleam@float:compare(A, B) of
        lt ->
            gt;

        eq ->
            eq;

        gt ->
            lt
    end.

-file("src/engine/feed.gleam", 69).
-spec sort_rising(list(engine@types:post())) -> list(engine@types:post()).
sort_rising(Posts) ->
    Now = os:system_time(millisecond),
    gleam@list:sort(
        Posts,
        fun(Post_a, Post_b) ->
            Score_a = rising_metric(Post_a, Now),
            Score_b = rising_metric(Post_b, Now),
            case compare_float_desc(Score_a, Score_b) of
                eq ->
                    compare_int_desc(
                        erlang:element(7, Post_a),
                        erlang:element(7, Post_b)
                    );

                Other ->
                    Other
            end
        end
    ).

-file("src/engine/feed.gleam", 11).
?DOC(" Feed utilities for sorting Reddit-style listings (hot/new/rising).\n").
-spec sort_posts(list(engine@types:post()), engine@types:feed_order()) -> list(engine@types:post()).
sort_posts(Posts, Order_by) ->
    case Order_by of
        hot ->
            sort_hot(Posts);

        new ->
            sort_new(Posts);

        rising ->
            sort_rising(Posts)
    end.

-file("src/engine/feed.gleam", 26).
-spec fetch_feed(
    gleam@erlang@process:subject(engine@content_coordinator:message()),
    list(integer()),
    engine@types:feed_order(),
    integer()
) -> {ok, list(engine@types:post())} | {error, nil}.
fetch_feed(Coordinator, Subreddits, Order_by, Limit) ->
    Response = gleam@erlang@process:try_call(
        Coordinator,
        fun(Responder) ->
            {list_posts_by_subreddits, Subreddits, Limit * 3, Responder}
        end,
        5000
    ),
    case Response of
        {error, _} ->
            {error, nil};

        {ok, Posts} ->
            {ok,
                begin
                    _pipe = Posts,
                    _pipe@1 = sort_posts(_pipe, Order_by),
                    truncate(_pipe@1, Limit)
                end}
    end.
