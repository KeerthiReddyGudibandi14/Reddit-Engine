-module(engine@ids).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/engine/ids.gleam").
-export([new/2, next/1, user_ids/1, subreddit_ids/1, post_ids/1, comment_ids/1, dm_thread_ids/1, message_ids/1]).
-export_type([id_generator/1]).

-type id_generator(ABO) :: {id_generator, integer(), fun((integer()) -> ABO)}.

-file("src/engine/ids.gleam", 22).
-spec new(integer(), fun((integer()) -> ABP)) -> id_generator(ABP).
new(Start_at, Wrap) ->
    {id_generator, Start_at, Wrap}.

-file("src/engine/ids.gleam", 26).
-spec next(id_generator(ABR)) -> {ABR, id_generator(ABR)}.
next(Generator) ->
    {id_generator, Counter, Wrap} = Generator,
    {Wrap(Counter), {id_generator, Counter + 1, Wrap}}.

-file("src/engine/ids.gleam", 31).
-spec user_ids(integer()) -> id_generator(integer()).
user_ids(Start_at) ->
    new(Start_at, fun(X) -> X end).

-file("src/engine/ids.gleam", 35).
-spec subreddit_ids(integer()) -> id_generator(integer()).
subreddit_ids(Start_at) ->
    new(Start_at, fun(X) -> X end).

-file("src/engine/ids.gleam", 39).
-spec post_ids(integer()) -> id_generator(integer()).
post_ids(Start_at) ->
    new(Start_at, fun(X) -> X end).

-file("src/engine/ids.gleam", 43).
-spec comment_ids(integer()) -> id_generator(integer()).
comment_ids(Start_at) ->
    new(Start_at, fun(X) -> X end).

-file("src/engine/ids.gleam", 47).
-spec dm_thread_ids(integer()) -> id_generator(integer()).
dm_thread_ids(Start_at) ->
    new(Start_at, fun(X) -> X end).

-file("src/engine/ids.gleam", 51).
-spec message_ids(integer()) -> id_generator(integer()).
message_ids(Start_at) ->
    new(Start_at, fun(X) -> X end).
