import database.{Badarg}
import gleam/dynamic/decode
import gleam/option.{None, Some}
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

pub type Person {
  Person(name: String, age: Int)
}

fn decoder() {
  use name <- database.field(0, decode.string)
  use age <- database.field(1, decode.int)
  decode.success(Person(name:, age:))
}

const definition = Person("Nome", 1)

/// Tests all public functions on their "happy path"
pub fn full_cicle_test() {
  let assert Ok(table) = database.create_table(definition, decoder())

  let _ =
    database.transaction(table, fn(ref) {
      let assert Ok(Nil) = database.insert(ref, Person("Sebastian Vettel", 87))
      let assert Ok(Nil) = database.insert(ref, Person("Max Verstappen", 29))
    })

  let _ =
    database.transaction(table, fn(ref) {
      let assert None = database.find(ref, "Oscar Piastri")
      let assert Some(Person("Sebastian Vettel", 87)) =
        database.find(ref, "Sebastian Vettel")
      let assert Ok(Nil) = database.delete(ref, "Sebastian Vettel")
      let assert None = database.find(ref, "Sebastian Vettel")
    })

  let assert Ok(_) = database.drop_table(table)
}

/// Tests whether the create_table function is type-safe
pub fn tables_without_records_test() {
  let assert Error(Badarg) = database.create_table("Person", decode.string)
  let assert Error(Badarg) = database.create_table(1234, decode.int)
  let assert Error(Badarg) = database.create_table(False, decode.bool)
  let sample = Person("Socrates", 7)
  let assert Ok(t) = database.create_table(sample, decoder())

  let assert Ok(_) = database.drop_table(t)
}

pub fn direct_operations_test() {
  let assert Ok(table) =
    database.create_table(definition:, decode_with: decoder())
  let assert Ok(_) =
    database.transaction(table, database.insert(_, Person("Your mom™", 2048)))
  let assert Ok(Some(Person("Your mom™", 2048))) =
    database.transaction(table, database.find(_, "Your mom™"))
  let assert Ok(_) = database.drop_table(table)
}

pub fn select_test() {
  let assert Ok(table) = database.create_table(definition, decoder())

  let _ =
    database.transaction(table, fn(ref) {
      let assert Ok(_) = database.insert(ref, Person("João", 23))
      let assert Ok(_) = database.insert(ref, Person("Someone very old", 101))
      let assert Ok(_) = database.insert(ref, Person("Maria", 55))
      let assert Ok(_) = database.insert(ref, Person("Not Maria", 56))
    })

  let assert Ok([_, _]) =
    database.transaction(table, fn(ref) {
      database.select(ref, fn(value) {
        case value {
          Person("João", _) -> database.Continue(value)
          Person(_, 55) -> database.Continue(value)
          _ -> database.Skip
        }
      })
    })

  let assert Ok([Person("João", 23)]) =
    database.transaction(table, fn(ref) {
      database.select(ref, fn(value) {
        case value {
          Person("João", _) -> database.Done(value)
          _ -> database.Skip
        }
      })
    })

  database.drop_table(table)
}
