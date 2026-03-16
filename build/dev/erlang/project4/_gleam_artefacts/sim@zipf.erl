-module(sim@zipf).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/sim/zipf.gleam").
-export([probability_for/2, size/1, probabilities/1, build/2, sample/2]).
-export_type([zipf_sampler/0, zipf_error/0]).

-type zipf_sampler() :: {zipf_sampler,
        integer(),
        float(),
        list(float()),
        list(float())}.

-type zipf_error() :: invalid_size | invalid_exponent | rank_out_of_bounds.

-file("src/sim/zipf.gleam", 49).
-spec probability_for(zipf_sampler(), integer()) -> {ok, float()} |
    {error, zipf_error()}.
probability_for(Sampler, Rank) ->
    case Rank < 1 of
        true ->
            {error, rank_out_of_bounds};

        false ->
            case gleam@list:drop(erlang:element(5, Sampler), Rank - 1) of
                [] ->
                    {error, rank_out_of_bounds};

                [Value | _] ->
                    {ok, Value}
            end
    end.

-file("src/sim/zipf.gleam", 63).
-spec size(zipf_sampler()) -> integer().
size(Sampler) ->
    erlang:element(2, Sampler).

-file("src/sim/zipf.gleam", 67).
-spec probabilities(zipf_sampler()) -> list(float()).
probabilities(Sampler) ->
    erlang:element(5, Sampler).

-file("src/sim/zipf.gleam", 81).
-spec term(integer(), float()) -> float().
term(Rank, Exponent) ->
    Neg_exp = gleam@float:negate(Exponent),
    case gleam@float:power(erlang:float(Rank), Neg_exp) of
        {ok, Value} ->
            Value;

        {error, _} ->
            +0.0
    end.

-file("src/sim/zipf.gleam", 71).
-spec harmonic(integer(), float()) -> float().
harmonic(Size, Exponent) ->
    _pipe = gleam@list:range(1, Size + 1),
    _pipe@1 = gleam@list:map(_pipe, fun(Rank) -> term(Rank, Exponent) end),
    gleam@float:sum(_pipe@1).

-file("src/sim/zipf.gleam", 77).
-spec probability(integer(), float(), float()) -> float().
probability(Rank, Exponent, Normalization) ->
    case Normalization of
        +0.0 -> +0.0;
        -0.0 -> -0.0;
        Gleam@denominator -> term(Rank, Exponent) / Gleam@denominator
    end.

-file("src/sim/zipf.gleam", 94).
-spec cumulative_loop(list(float()), float(), list(float())) -> list(float()).
cumulative_loop(Values, Total, Acc) ->
    case Values of
        [] ->
            Acc;

        [Head | Tail] ->
            Next_total = Total + Head,
            cumulative_loop(Tail, Next_total, [Next_total | Acc])
    end.

-file("src/sim/zipf.gleam", 89).
-spec cumulative(list(float())) -> list(float()).
cumulative(Values) ->
    _pipe = cumulative_loop(Values, +0.0, []),
    lists:reverse(_pipe).

-file("src/sim/zipf.gleam", 23).
-spec build(integer(), float()) -> {ok, zipf_sampler()} | {error, zipf_error()}.
build(Size, Exponent) ->
    case {Size > 0, Exponent > +0.0} of
        {true, true} ->
            Normalization = harmonic(Size, Exponent),
            Probabilities = begin
                _pipe = gleam@list:range(1, Size + 1),
                gleam@list:map(
                    _pipe,
                    fun(Rank) -> probability(Rank, Exponent, Normalization) end
                )
            end,
            Cdf = cumulative(Probabilities),
            {ok, {zipf_sampler, Size, Exponent, Cdf, Probabilities}};

        {false, _} ->
            {error, invalid_size};

        {_, false} ->
            {error, invalid_exponent}
    end.

-file("src/sim/zipf.gleam", 108).
-spec sample_loop(list(float()), float(), integer(), integer()) -> integer().
sample_loop(Cdf, Target, Rank, Max_rank) ->
    case Cdf of
        [] ->
            Max_rank;

        [Head | Tail] ->
            case Target =< Head of
                true ->
                    Rank;

                false ->
                    sample_loop(Tail, Target, Rank + 1, Max_rank)
            end
    end.

-file("src/sim/zipf.gleam", 44).
-spec sample(zipf_sampler(), float()) -> integer().
sample(Sampler, U) ->
    Clamped = gleam@float:clamp(U, +0.0, 0.999999),
    sample_loop(
        erlang:element(4, Sampler),
        Clamped,
        1,
        erlang:element(2, Sampler)
    ).
