-module(engine@actor_user_registry_test).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "test/engine/actor_user_registry_test.gleam").
-export([main/0, register_and_lookup_user_test/0, adjust_karma_updates_user_test/0]).

-file("test/engine/actor_user_registry_test.gleam", 7).
-spec main() -> nil.
main() ->
    gleeunit:main().

-file("test/engine/actor_user_registry_test.gleam", 11).
-spec register_and_lookup_user_test() -> nil.
register_and_lookup_user_test() ->
    Subject@1 = case engine@user_registry:start() of
        {ok, Subject} -> Subject;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_user_registry_test"/utf8>>,
                        function => <<"register_and_lookup_user_test"/utf8>>,
                        line => 12,
                        value => _assert_fail,
                        start => 203,
                        'end' => 249,
                        pattern_start => 214,
                        pattern_end => 225})
    end,
    Register_result = gleam@erlang@process:call(
        Subject@1,
        fun(Responder) -> {register, <<"alice"/utf8>>, Responder} end,
        1000
    ),
    User@1 = case Register_result of
        {ok, User} -> User;
        _assert_fail@1 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_user_registry_test"/utf8>>,
                        function => <<"register_and_lookup_user_test"/utf8>>,
                        line => 19,
                        value => _assert_fail@1,
                        start => 398,
                        'end' => 435,
                        pattern_start => 409,
                        pattern_end => 417})
    end,
    gleeunit@should:equal(erlang:element(3, User@1), <<"alice"/utf8>>),
    Lookup_result = gleam@erlang@process:call(
        Subject@1,
        fun(Responder@1) -> {lookup_by_name, <<"alice"/utf8>>, Responder@1} end,
        1000
    ),
    Found@1 = case Lookup_result of
        {some, Found} -> Found;
        _assert_fail@2 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_user_registry_test"/utf8>>,
                        function => <<"register_and_lookup_user_test"/utf8>>,
                        line => 27,
                        value => _assert_fail@2,
                        start => 621,
                        'end' => 666,
                        pattern_start => 632,
                        pattern_end => 650})
    end,
    gleeunit@should:equal(erlang:element(2, Found@1), erlang:element(2, User@1)).

-file("test/engine/actor_user_registry_test.gleam", 31).
-spec adjust_karma_updates_user_test() -> nil.
adjust_karma_updates_user_test() ->
    Subject@1 = case engine@user_registry:start() of
        {ok, Subject} -> Subject;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_user_registry_test"/utf8>>,
                        function => <<"adjust_karma_updates_user_test"/utf8>>,
                        line => 32,
                        value => _assert_fail,
                        start => 748,
                        'end' => 794,
                        pattern_start => 759,
                        pattern_end => 770})
    end,
    User@1 = case gleam@erlang@process:call(
        Subject@1,
        fun(Responder) -> {register, <<"karma_user"/utf8>>, Responder} end,
        1000
    ) of
        {ok, User} -> User;
        _assert_fail@1 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_user_registry_test"/utf8>>,
                        function => <<"adjust_karma_updates_user_test"/utf8>>,
                        line => 34,
                        value => _assert_fail@1,
                        start => 798,
                        'end' => 944,
                        pattern_start => 809,
                        pattern_end => 817})
    end,
    Updated@1 = case gleam@erlang@process:call(
        Subject@1,
        fun(Responder@1) ->
            {adjust_karma, erlang:element(2, User@1), 5, Responder@1}
        end,
        1000
    ) of
        {ok, Updated} -> Updated;
        _assert_fail@2 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_user_registry_test"/utf8>>,
                        function => <<"adjust_karma_updates_user_test"/utf8>>,
                        line => 39,
                        value => _assert_fail@2,
                        start => 948,
                        'end' => 1103,
                        pattern_start => 959,
                        pattern_end => 970})
    end,
    gleeunit@should:equal(erlang:element(5, Updated@1), 5),
    Updated_again@1 = case gleam@erlang@process:call(
        Subject@1,
        fun(Responder@2) ->
            {adjust_karma, erlang:element(2, User@1), -2, Responder@2}
        end,
        1000
    ) of
        {ok, Updated_again} -> Updated_again;
        _assert_fail@3 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_user_registry_test"/utf8>>,
                        function => <<"adjust_karma_updates_user_test"/utf8>>,
                        line => 46,
                        value => _assert_fail@3,
                        start => 1141,
                        'end' => 1303,
                        pattern_start => 1152,
                        pattern_end => 1169})
    end,
    gleeunit@should:equal(erlang:element(5, Updated_again@1), 3).
