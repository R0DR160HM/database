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
import gleam/dynamic/decode

type Music {
  Music(name: String, release_year: Int)
}

fn music_decoder() {
  use name <- database.field(0, decode.string)
  use release_year <- database.field(1, decode.int)
  decode.success(Music(name:, release_year:))
}

pub fn main() -> Nil {
  let assert Ok(table) = database.create_table(
    name: "musics", 
    decode_with: music_decoder())

  // All interactions with the table happen within a transaction
  let assert Ok(castemere_id) = database.transaction(table, fn(ref) {
    let assert Ok(id) = database.insert(ref, Music("The Rains of Castemere", 2019))
    id
  })

  // You can do multiple operations within the same transaction, as long as they don't interact with each other
  let assert Ok(templars_id) = database.transaction(table, fn(ref) {
    let assert Ok(id) = database.insert(ref, Music("Templars", 2025))
    let assert Ok(_) = database.insert(ref, Music("Kids", 2009))
    let assert Ok(Nil) = database.delete(ref, castemere_id)
    id
  })

  // You can find elements by their primary_key...
  let _ = database.transaction(table, fn(ref) {
    let assert option.None = database.find(ref, castemere_id)
    let assert option.Some(Music("Templars", 2025)) = database.find(ref, templars_id)
  })

  // [...] or by complex queries
  let assert Ok([_, _]) = database.transaction(table, fn(ref) {
    database.select(ref, fn(value) {
      case value {
        #(_id, Music(_name, year)) if year > 2000 -> database.Continue(value)
        _ -> database.Skip
      }
    })
  })
}
```

Further documentation can be found at <https://hexdocs.pm/database>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
