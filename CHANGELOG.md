# Changelog

## 5.0.0 - In Memory We Trust 
- Support for the ETS api
    * Functions `create_dets_table` and `create_ets_table` created, each to their own specific table type.
    * Function `create_table` deprecated. Now just an alias for `create_dets_table`.
    * Functions `insert`, `update`, `delete`, `find` and `drop_table` changed to support ETS, their signatures remain the same.
    * Function `migrate` renamed to `migrate_dets` to highlight its exclusivity to that table type.
- Function `transaction`, together with the new `TransactionError` type, now flattens its result. No more `Ok(Ok(result))` or, even worse, `Ok(Error(reason))`, just `Ok(result)` or `Error(reason)`
- Function `select` completely rewritten, together with the creation of the `SelectError` type, so it now works through native Erlang pattern matching (hidden behind a type-safe API).
- Function `upsert` created, allowing to - finally - save a value with your own ID, instead of relying on a randomly generated one.

##  4.0.0
- `table_name` parameter in `create_table` function is now an Atom, so that the AtomTable is always **knowingly** populated **by the developer**.
- Documentation changed to reflect the preferred `use`-based code style.
- New error type `FindError` returned by the `find` function, which became a `Result` instead of an `Option`.
