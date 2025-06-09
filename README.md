# Database

A BEAM-native database that leverages on the power of DETS

[![Package Version](https://img.shields.io/hexpm/v/database)](https://hex.pm/packages/database)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/database/)

```sh
gleam add database
```
```gleam
import database
import gleam/option

type Music {
  Music(name: String, release_year: String)
}

// The generated table will be entirely based on this definition,
// and any change to the definition will casue a different table
// to be created.
// So make sure the type fits all your requirements before making
// a table out of it.
const music_table_def = Music(name: "Music name", year: 0000)

pub fn main() -> Nil {
  // 0 indicates that the table primary_key is the 0th value (name)
  let assert Ok(table) = database.create_table(
    definition: music_table_def, 
    index_at: 0)

  // All interactions with the table happen within a transaction
  let assert Ok(Nil) = database.transaction(table, fn(ref) {
    database.insert(ref, Music("The Rains of Castemere", 2019))
  })

  // You can do multiple operations within the same transaction, as long as they don't interact with each other
  let _ = database.transaction(table, fn(ref) {
    let assert Ok(Nil) = database.insert(ref, Music("Templars", 2025))
    let assert Ok(Nil) = database.insert(ref, Music("Kids", 2009))
    let assert Ok(Nil) = database.delete(ref, "The Rains of Castemere")
  })

  let _ = database.transaction(table, fn(ref) {
    let assert option.None = database.find(ref, "The Rains of Castemere")
    let assert option.Some(Music("Templars", 2025)) = database.find(ref, "Templars")
  })
}
```

Further documentation can be found at <https://hexdocs.pm/database>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
