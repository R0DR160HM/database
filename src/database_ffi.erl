-module(database_ffi).

-export([compare/2, skip/0]).

compare(A, B) ->
    A =:= B.

skip() -> continue.
