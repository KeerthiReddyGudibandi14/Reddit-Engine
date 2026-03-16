-module(engine@actor_dm_router_test).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "test/engine/actor_dm_router_test.gleam").
-export([main/0, send_and_reply_dm_test/0]).

-file("test/engine/actor_dm_router_test.gleam", 8).
-spec main() -> nil.
main() ->
    gleeunit:main().

-file("test/engine/actor_dm_router_test.gleam", 12).
-spec send_and_reply_dm_test() -> nil.
send_and_reply_dm_test() ->
    Router@1 = case engine@dm_router:start() of
        {ok, Router} -> Router;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_dm_router_test"/utf8>>,
                        function => <<"send_and_reply_dm_test"/utf8>>,
                        line => 13,
                        value => _assert_fail,
                        start => 210,
                        'end' => 251,
                        pattern_start => 221,
                        pattern_end => 231})
    end,
    Message@1 = case gleam@erlang@process:call(
        Router@1,
        fun(Responder) -> {send_new, 1, 2, <<"hello"/utf8>>, Responder} end,
        1000
    ) of
        {ok, Message} -> Message;
        _assert_fail@1 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_dm_router_test"/utf8>>,
                        function => <<"send_and_reply_dm_test"/utf8>>,
                        line => 15,
                        value => _assert_fail@1,
                        start => 255,
                        'end' => 450,
                        pattern_start => 266,
                        pattern_end => 277})
    end,
    gleeunit@should:equal(erlang:element(6, Message@1), <<"hello"/utf8>>),
    Inbox = gleam@erlang@process:call(
        Router@1,
        fun(Responder@1) -> {list_inbox, 2, Responder@1} end,
        1000
    ),
    gleeunit@should:equal(erlang:length(Inbox), 1),
    Reply_message@1 = case gleam@erlang@process:call(
        Router@1,
        fun(Responder@2) ->
            {reply,
                erlang:element(3, Message@1),
                2,
                <<"hi back"/utf8>>,
                Responder@2}
        end,
        1000
    ) of
        {ok, Reply_message} -> Reply_message;
        _assert_fail@2 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_dm_router_test"/utf8>>,
                        function => <<"send_and_reply_dm_test"/utf8>>,
                        line => 34,
                        value => _assert_fail@2,
                        start => 641,
                        'end' => 859,
                        pattern_start => 652,
                        pattern_end => 669})
    end,
    gleeunit@should:equal(
        erlang:element(8, Reply_message@1),
        {some, erlang:element(2, Message@1)}
    ),
    Thread_messages@1 = case gleam@erlang@process:call(
        Router@1,
        fun(Responder@3) ->
            {list_thread, erlang:element(3, Message@1), 1, Responder@3}
        end,
        1000
    ) of
        {ok, Thread_messages} -> Thread_messages;
        _assert_fail@3 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_dm_router_test"/utf8>>,
                        function => <<"send_and_reply_dm_test"/utf8>>,
                        line => 46,
                        value => _assert_fail@3,
                        start => 931,
                        'end' => 1136,
                        pattern_start => 942,
                        pattern_end => 961})
    end,
    gleeunit@should:equal(erlang:length(Thread_messages@1), 2).
