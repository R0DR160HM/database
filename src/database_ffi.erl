-module(database_ffi).

-export([compare/2, safe_dets_select/2, format_select_pattern/1, format_single_pattern/1]).

compare(A, B) ->
    A =:= B.

safe_dets_select(Name, Spec) ->
    case dets:select(Name, Spec) of
        {error, Reason} -> {error, Reason};
        Objects when is_list(Objects) -> {ok, Objects}
    end.

format_select_pattern(Tuple) when is_tuple(Tuple) ->
    List = erlang:tuple_to_list(Tuple),
    {ok, lists:map(fun format_single_pattern/1, List)}; 
format_select_pattern(_Else) ->                         
    {error, nil}.                                      

format_single_pattern(Fun) when is_function(Fun) ->
    {arity, Arity} = erlang:fun_info(Fun, arity),
    Args = lists:duplicate(Arity, '_'),
    {{'_', erlang:apply(Fun, Args)}, [], ['$_']};    
format_single_pattern(Value) ->
    {{'_', Value}, [], ['$_']}.                     
