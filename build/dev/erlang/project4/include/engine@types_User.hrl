-record(user, {
    id :: integer(),
    name :: binary(),
    joined_subreddits :: gleam@set:set(integer()),
    karma :: integer()
}).
