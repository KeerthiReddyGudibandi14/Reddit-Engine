-module(engine@actor_content_coordinator_test).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "test/engine/actor_content_coordinator_test.gleam").
-export([main/0, post_comment_vote_flow_test/0]).

-file("test/engine/actor_content_coordinator_test.gleam", 11).
-spec main() -> nil.
main() ->
    gleeunit:main().

-file("test/engine/actor_content_coordinator_test.gleam", 15).
-spec post_comment_vote_flow_test() -> nil.
post_comment_vote_flow_test() ->
    User_registry_subject@1 = case engine@user_registry:start() of
        {ok, User_registry_subject} -> User_registry_subject;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_content_coordinator_test"/utf8>>,
                        function => <<"post_comment_vote_flow_test"/utf8>>,
                        line => 16,
                        value => _assert_fail,
                        start => 306,
                        'end' => 366,
                        pattern_start => 317,
                        pattern_end => 342})
    end,
    Author@1 = case gleam@erlang@process:call(
        User_registry_subject@1,
        fun(Responder) -> {register, <<"author"/utf8>>, Responder} end,
        1000
    ) of
        {ok, Author} -> Author;
        _assert_fail@1 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_content_coordinator_test"/utf8>>,
                        function => <<"post_comment_vote_flow_test"/utf8>>,
                        line => 17,
                        value => _assert_fail@1,
                        start => 369,
                        'end' => 527,
                        pattern_start => 380,
                        pattern_end => 390})
    end,
    Voter@1 = case gleam@erlang@process:call(
        User_registry_subject@1,
        fun(Responder@1) -> {register, <<"voter"/utf8>>, Responder@1} end,
        1000
    ) of
        {ok, Voter} -> Voter;
        _assert_fail@2 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_content_coordinator_test"/utf8>>,
                        function => <<"post_comment_vote_flow_test"/utf8>>,
                        line => 21,
                        value => _assert_fail@2,
                        start => 530,
                        'end' => 686,
                        pattern_start => 541,
                        pattern_end => 550})
    end,
    Subreddit_registry_subject@1 = case engine@subreddit_registry:start(
        User_registry_subject@1
    ) of
        {ok, Subreddit_registry_subject} -> Subreddit_registry_subject;
        _assert_fail@3 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_content_coordinator_test"/utf8>>,
                        function => <<"post_comment_vote_flow_test"/utf8>>,
                        line => 26,
                        value => _assert_fail@3,
                        start => 690,
                        'end' => 785,
                        pattern_start => 701,
                        pattern_end => 731})
    end,
    Subreddit@1 = case gleam@erlang@process:call(
        Subreddit_registry_subject@1,
        fun(Responder@2) ->
            {create, <<"test"/utf8>>, erlang:element(2, Author@1), Responder@2}
        end,
        1000
    ) of
        {ok, Subreddit} -> Subreddit;
        _assert_fail@4 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_content_coordinator_test"/utf8>>,
                        function => <<"post_comment_vote_flow_test"/utf8>>,
                        line => 29,
                        value => _assert_fail@4,
                        start => 789,
                        'end' => 976,
                        pattern_start => 800,
                        pattern_end => 813})
    end,
    case gleam@erlang@process:call(
        Subreddit_registry_subject@1,
        fun(Responder@3) ->
            {join,
                erlang:element(2, Subreddit@1),
                erlang:element(2, Voter@1),
                Responder@3}
        end,
        1000
    ) of
        {ok, _} -> nil;
        _assert_fail@5 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_content_coordinator_test"/utf8>>,
                        function => <<"post_comment_vote_flow_test"/utf8>>,
                        line => 34,
                        value => _assert_fail@5,
                        start => 980,
                        'end' => 1197,
                        pattern_start => 991,
                        pattern_end => 996})
    end,
    Coordinator_subject@1 = case engine@content_coordinator:start(
        User_registry_subject@1,
        Subreddit_registry_subject@1
    ) of
        {ok, Coordinator_subject} -> Coordinator_subject;
        _assert_fail@6 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_content_coordinator_test"/utf8>>,
                        function => <<"post_comment_vote_flow_test"/utf8>>,
                        line => 43,
                        value => _assert_fail@6,
                        start => 1201,
                        'end' => 1318,
                        pattern_start => 1212,
                        pattern_end => 1235})
    end,
    Post@1 = case gleam@erlang@process:call(
        Coordinator_subject@1,
        fun(Responder@4) ->
            {create_post,
                erlang:element(2, Author@1),
                erlang:element(2, Subreddit@1),
                <<"hello world"/utf8>>,
                Responder@4}
        end,
        1000
    ) of
        {ok, Post} -> Post;
        _assert_fail@7 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_content_coordinator_test"/utf8>>,
                        function => <<"post_comment_vote_flow_test"/utf8>>,
                        line => 46,
                        value => _assert_fail@7,
                        start => 1322,
                        'end' => 1574,
                        pattern_start => 1333,
                        pattern_end => 1341})
    end,
    gleeunit@should:equal(
        erlang:element(4, Post@1),
        erlang:element(2, Author@1)
    ),
    Fetched_post@1 = case gleam@erlang@process:call(
        Coordinator_subject@1,
        fun(Responder@5) ->
            {fetch_post, erlang:element(2, Post@1), Responder@5}
        end,
        1000
    ) of
        {some, Fetched_post} -> Fetched_post;
        _assert_fail@8 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_content_coordinator_test"/utf8>>,
                        function => <<"post_comment_vote_flow_test"/utf8>>,
                        line => 58,
                        value => _assert_fail@8,
                        start => 1618,
                        'end' => 1779,
                        pattern_start => 1629,
                        pattern_end => 1654})
    end,
    gleeunit@should:equal(
        erlang:element(5, Fetched_post@1),
        <<"hello world"/utf8>>
    ),
    Comment@1 = case gleam@erlang@process:call(
        Coordinator_subject@1,
        fun(Responder@6) ->
            {create_comment,
                erlang:element(2, Author@1),
                erlang:element(2, Post@1),
                none,
                <<"first!"/utf8>>,
                Responder@6}
        end,
        1000
    ) of
        {ok, Comment} -> Comment;
        _assert_fail@9 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_content_coordinator_test"/utf8>>,
                        function => <<"post_comment_vote_flow_test"/utf8>>,
                        line => 65,
                        value => _assert_fail@9,
                        start => 1833,
                        'end' => 2105,
                        pattern_start => 1844,
                        pattern_end => 1855})
    end,
    gleeunit@should:equal(
        erlang:element(3, Comment@1),
        erlang:element(2, Post@1)
    ),
    Comments = gleam@erlang@process:call(
        Coordinator_subject@1,
        fun(Responder@7) ->
            {fetch_comments, erlang:element(2, Post@1), Responder@7}
        end,
        1000
    ),
    gleeunit@should:equal(erlang:length(Comments), 1),
    Updated_post@1 = case gleam@erlang@process:call(
        Coordinator_subject@1,
        fun(Responder@8) ->
            {vote_on_post,
                erlang:element(2, Voter@1),
                erlang:element(2, Post@1),
                upvote,
                Responder@8}
        end,
        1000
    ) of
        {ok, Updated_post} -> Updated_post;
        _assert_fail@10 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"engine/actor_content_coordinator_test"/utf8>>,
                        function => <<"post_comment_vote_flow_test"/utf8>>,
                        line => 85,
                        value => _assert_fail@10,
                        start => 2335,
                        'end' => 2582,
                        pattern_start => 2346,
                        pattern_end => 2362})
    end,
    gleeunit@should:equal(
        erlang:element(7, Updated_post@1),
        erlang:element(7, Post@1) + 1
    ).
