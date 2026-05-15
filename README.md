# Database

A BEAM-native database that leverages on the power of ETS and DETS

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

pub fn main() -> Nil {
  let table_name = atom.create("musics")
  let table = database.create_ets_table(table_name)

  // All interactions with the table happen within a transaction
  let assert Ok(castemere_id) = {
    use ref <- database.transaction(table)
    // Every insert auto generates a random string ID for the data
    database.insert(ref, Music("The Rains of Castemere", Movie, 2019))
  }

  // You can do multiple operations within the same transaction, 
  // as long as they don't interact with each other
  let assert Ok(templars_id) = {
    use ref <- database.transaction(table)
    let assert Ok(id) = database.insert(transac, Music("Templars", Rock, 2025))
    let assert Ok(_) = database.insert(transac, Music("Kids", Electro, 2009))
    let assert Ok(Nil) = database.delete(ref, castemere_id)
    Ok(id)
  }

  // You can find elements by their id...
  let _ = {
    use ref <- database.transaction(table)
    // Already deleted
    assert Error(database.NotFound) == database.find(ref, castemere_id)
    // Still exists
    assert Ok(Music("Templars", Rock, 2025)) == database.find(ref, templars_id)
  }

  // [...] or by complex queries
  let assert Ok([_, _]) = {
    use ref <- database.transaction(table)
    database.select(ref, #(Music(_, Rock, 2025)))
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
