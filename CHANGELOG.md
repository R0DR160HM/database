#  4.0.0
- `table_name` parameter in `create_table` function is now an Atom, so that the AtomTable is always **knowingly** populated **by the developer**.
- Documentation changed to reflect the preferred `use`-based code style.
- New error type `FindError` returned by the `find` function, which became a `Result` instead of an `Option`.
