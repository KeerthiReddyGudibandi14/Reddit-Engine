-module(engine@actor_subreddit_registry_test).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "test/engine/actor_subreddit_registry_test.gleam").
-export([main/0, create_join_leave_subreddit_test/0]).

-file("test/engine/actor_subreddit_registry_test.gleam", 9).
-spec main() -> nil.
main() ->
    gleeunit:main().

-file("test/engine/actor_subreddit_registry_test.gleam", 13).
-spec create_join_leave_subreddit_test() -> nil.
create_join_leave_subreddit_test() ->
    User_registry_subject@1 = case engine@user_registry:start() of
        {ok, User_registry_subject} -> User_registry_subject;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_subreddit_registry_test"/utf8>>,
                        function => <<"create_join_leave_subreddit_test"/utf8>>,
                        line => 14,
                        value => _assert_fail,
                        start => 256,
                        'end' => 316,
                        pattern_start => 267,
                        pattern_end => 292})
    end,
    Creator@1 = case gleam@erlang@process:call(
        User_registry_subject@1,
        fun(Responder) -> {register, <<"creator"/utf8>>, Responder} end,
        1000
    ) of
        {ok, Creator} -> Creator;
        _assert_fail@1 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_subreddit_registry_test"/utf8>>,
                        function => <<"create_join_leave_subreddit_test"/utf8>>,
                        line => 15,
                        value => _assert_fail@1,
                        start => 319,
                        'end' => 479,
                        pattern_start => 330,
                        pattern_end => 341})
    end,
    Subreddit_registry_subject@1 = case engine@subreddit_registry:start(
        User_registry_subject@1
    ) of
        {ok, Subreddit_registry_subject} -> Subreddit_registry_subject;
        _assert_fail@2 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_subreddit_registry_test"/utf8>>,
                        function => <<"create_join_leave_subreddit_test"/utf8>>,
                        line => 20,
                        value => _assert_fail@2,
                        start => 483,
                        'end' => 578,
                        pattern_start => 494,
                        pattern_end => 524})
    end,
    Created_subreddit@1 = case gleam@erlang@process:call(
        Subreddit_registry_subject@1,
        fun(Responder@1) ->
            {create,
                <<"gleam"/utf8>>,
                erlang:element(2, Creator@1),
                Responder@1}
        end,
        1000
    ) of
        {ok, Created_subreddit} -> Created_subreddit;
        _assert_fail@3 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_subreddit_registry_test"/utf8>>,
                        function => <<"create_join_leave_subreddit_test"/utf8>>,
                        line => 23,
                        value => _assert_fail@3,
                        start => 582,
                        'end' => 779,
                        pattern_start => 593,
                        pattern_end => 614})
    end,
    gleeunit@should:equal(
        gleam@set:contains(
            erlang:element(4, Created_subreddit@1),
            erlang:element(2, Creator@1)
        ),
        true
    ),
    Other_user@1 = case gleam@erlang@process:call(
        User_registry_subject@1,
        fun(Responder@2) -> {register, <<"second"/utf8>>, Responder@2} end,
        1000
    ) of
        {ok, Other_user} -> Other_user;
        _assert_fail@4 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_subreddit_registry_test"/utf8>>,
                        function => <<"create_join_leave_subreddit_test"/utf8>>,
                        line => 30,
                        value => _assert_fail@4,
                        start => 858,
                        'end' => 1020,
                        pattern_start => 869,
                        pattern_end => 883})
    end,
    case gleam@erlang@process:call(
        Subreddit_registry_subject@1,
        fun(Responder@3) ->
            {join,
                erlang:element(2, Created_subreddit@1),
                erlang:element(2, Other_user@1),
                Responder@3}
        end,
        1000
    ) of
        {ok, _} -> nil;
        _assert_fail@5 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_subreddit_registry_test"/utf8>>,
                        function => <<"create_join_leave_subreddit_test"/utf8>>,
                        line => 35,
                        value => _assert_fail@5,
                        start => 1024,
                        'end' => 1254,
                        pattern_start => 1035,
                        pattern_end => 1040})
    end,
    Joined_snapshot@1 = case gleam@erlang@process:call(
        Subreddit_registry_subject@1,
        fun(Responder@4) ->
            {lookup_by_id, erlang:element(2, Created_subreddit@1), Responder@4}
        end,
        1000
    ) of
        {some, Joined_snapshot} -> Joined_snapshot;
        _assert_fail@6 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_subreddit_registry_test"/utf8>>,
                        function => <<"create_join_leave_subreddit_test"/utf8>>,
                        line => 44,
                        value => _assert_fail@6,
                        start => 1258,
                        'end' => 1488,
                        pattern_start => 1269,
                        pattern_end => 1297})
    end,
    gleeunit@should:equal(
        gleam@set:contains(
            erlang:element(4, Joined_snapshot@1),
            erlang:element(2, Other_user@1)
        ),
        true
    ),
    case gleam@erlang@process:call(
        Subreddit_registry_subject@1,
        fun(Responder@5) ->
            {leave,
                erlang:element(2, Created_subreddit@1),
                erlang:element(2, Other_user@1),
                Responder@5}
        end,
        1000
    ) of
        {ok, _} -> nil;
        _assert_fail@7 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_subreddit_registry_test"/utf8>>,
                        function => <<"create_join_leave_subreddit_test"/utf8>>,
                        line => 54,
                        value => _assert_fail@7,
                        start => 1568,
                        'end' => 1799,
                        pattern_start => 1579,
                        pattern_end => 1584})
    end,
    Left_snapshot@1 = case gleam@erlang@process:call(
        Subreddit_registry_subject@1,
        fun(Responder@6) ->
            {lookup_by_id, erlang:element(2, Created_subreddit@1), Responder@6}
        end,
        1000
    ) of
        {some, Left_snapshot} -> Left_snapshot;
        _assert_fail@8 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_subreddit_registry_test"/utf8>>,
                        function => <<"create_join_leave_subreddit_test"/utf8>>,
                        line => 63,
                        value => _assert_fail@8,
                        start => 1803,
                        'end' => 2031,
                        pattern_start => 1814,
                        pattern_end => 1840})
    end,
    gleeunit@should:equal(
        gleam@set:contains(
            erlang:element(4, Left_snapshot@1),
            erlang:element(2, Other_user@1)
        ),
        false
    ).
