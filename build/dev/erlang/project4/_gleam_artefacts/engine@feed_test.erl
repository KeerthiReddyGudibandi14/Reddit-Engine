-module(engine@feed_test).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "test/engine/feed_test.gleam").
-export([main/0, sort_rising_orders_test/0, sort_hot_orders_by_score_test/0, sort_new_orders_by_timestamp_test/0]).

-file("test/engine/feed_test.gleam", 8).
-spec main() -> nil.
main() ->
    gleeunit:main().

-file("test/engine/feed_test.gleam", 26).
-spec sort_rising_orders_test() -> nil.
sort_rising_orders_test() ->
    Now = os:system_time(millisecond),
    Posts = [{post, 1, 1, 1, <<"first"/utf8>>, Now - 1000, 10},
        {post, 2, 1, 2, <<"second"/utf8>>, Now - 200, 5},
        {post, 3, 1, 3, <<"third"/utf8>>, Now - 400, 8}],
    Ordered = engine@feed:sort_posts(Posts, rising),
    Expected = [2, 3, 1],
    gleeunit@should:equal(
        gleam@list:map(Ordered, fun(P) -> erlang:element(2, P) end),
        Expected
    ).

-file("test/engine/feed_test.gleam", 38).
-spec sample_posts() -> list(engine@types:post()).
sample_posts() ->
    [{post, 1, 1, 1, <<"first"/utf8>>, 100, 10},
        {post, 2, 1, 2, <<"second"/utf8>>, 200, 5},
        {post, 3, 1, 3, <<"third"/utf8>>, 150, 8}].

-file("test/engine/feed_test.gleam", 12).
-spec sort_hot_orders_by_score_test() -> nil.
sort_hot_orders_by_score_test() ->
    Posts = sample_posts(),
    Ordered = engine@feed:sort_posts(Posts, hot),
    Expected = [1, 3, 2],
    gleeunit@should:equal(
        gleam@list:map(Ordered, fun(P) -> erlang:element(2, P) end),
        Expected
    ).

-file("test/engine/feed_test.gleam", 19).
-spec sort_new_orders_by_timestamp_test() -> nil.
sort_new_orders_by_timestamp_test() ->
    Posts = sample_posts(),
    Ordered = engine@feed:sort_posts(Posts, new),
    Expected = [2, 3, 1],
    gleeunit@should:equal(
        gleam@list:map(Ordered, fun(P) -> erlang:element(2, P) end),
        Expected
    ).
