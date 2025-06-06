# Database

A BEAM-native database that leverages on the power of DETS

[![Package Version](https://img.shields.io/hexpm/v/database)](https://hex.pm/packages/database)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/database/)

```sh
gleam add database
```
```gleam
import database

type Music {
  Music(name: String, release_year: String)
}

pub fn main() -> Nil {
  let sample = Music("Macarena", 1993)

  // 0 indicates that the table primary_key is the 0th value (name)
  let assert Ok(table) = database.create_table(sample, 0)

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
    let assert Error(Nil) = database.find(ref, "The Rains of Castemere")
    let assert Ok(Music("Templars", 2025)) = database.find(ref, "Templars")
  })
}
```

Further documentation can be found at <https://hexdocs.pm/database>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
