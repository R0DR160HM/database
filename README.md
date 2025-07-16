# Database

A BEAM-native database that leverages on the power of DETS

[![Package Version](https://img.shields.io/hexpm/v/database)](https://hex.pm/packages/database)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/database/)

```sh
gleam add database
```

```gleam

import database
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/io

type Genre {
  Rock
  Metal
  Pop
  Electro
  Movie
}

type Music {
  Music(name: String, genre: Genre, release_year: Int)
}

// The decoder teaches the database how to handle your data
fn table_decoder() {
  let genre_decoder = database.enum([Rock, Metal, Electro, Pop, Movie], Pop)

  use name <- database.field(0, decode.string)
  use genre <- database.field(1, genre_decoder)
  use release_year <- database.field(2, decode.int)
  decode.success(Music(name:, genre:, release_year:))
}

pub fn main() -> Nil {
  let table_name = atom.create("musics")
  let assert Ok(table) = database.create_table(table_name, table_decoder())

  // All interactions with the table happen within a transaction
  let assert Ok(castemere_id) = {
    use transac <- database.transaction(table)
    let assert Ok(id) =
      database.insert(transac, Music("The Rains of Castemere", Movie, 2019))
    // Every insert auto generates a random string ID for the data
    id
  }

  // You can do multiple operations within the same transaction, 
  // as long as tye don't interact with each other
  let assert Ok(templars_id) = {
    use transac <- database.transaction(table)
    let assert Ok(id) = database.insert(transac, Music("Templars", Rock, 2025))
    let assert Ok(_) = database.insert(transac, Music("Kids", Electro, 2009))
    let assert Ok(Nil) = database.delete(transac, castemere_id)
    id
  }

  // You can find elements by their id...
  let _ = {
    use transac <- database.transaction(table)
    // Already deleted
    assert Error(database.NotFound) == database.find(transac, castemere_id)
    // Still exists
    assert Ok(Music("Templars", Rock, 2025)) == database.find(transac, templars_id)
  }

  // [...] or by complex queries
  let assert Ok([_, _]) = {
    use transac <- database.transaction(table)
    use value <- database.select(transac)
    case value {
      // Selects only musics released after 2000
      #(_id, Music(_name, _genre, year)) if year > 2000 ->
        database.Continue(value)
      _ -> database.Skip
    }
  }

  io.println("And that's it, folks!")
}

```

Further documentation can be found at <https://hexdocs.pm/database>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
