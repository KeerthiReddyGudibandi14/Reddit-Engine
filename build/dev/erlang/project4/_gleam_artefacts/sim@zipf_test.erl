-module(sim@zipf_test).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "test/sim/zipf_test.gleam").
-export([main/0, probabilities_sum_to_one_test/0]).

-file("test/sim/zipf_test.gleam", 6).
-spec main() -> nil.
main() ->
    gleeunit:main().

-file("test/sim/zipf_test.gleam", 10).
-spec probabilities_sum_to_one_test() -> nil.
probabilities_sum_to_one_test() ->
    Sampler@1 = case sim@zipf:build(20, 1.2) of
        {ok, Sampler} -> Sampler;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"sim/zipf_test"/utf8>>,
                        function => <<"probabilities_sum_to_one_test"/utf8>>,
                        line => 11,
                        value => _assert_fail,
                        start => 162,
                        'end' => 206,
                        pattern_start => 173,
                        pattern_end => 184})
    end,
    Total = begin
        _pipe = Sampler@1,
        _pipe@1 = sim@zipf:probabilities(_pipe),
        gleam@float:sum(_pipe@1)
    end,
    gleeunit@should:be_true(gleam@float:absolute_value(Total - 1.0) < 0.0001).
