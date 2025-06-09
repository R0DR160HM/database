import database.{Badarg, IndexOutOfBounds}
import gleam/option.{None, Some}
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

pub type Person {
  Person(name: String, age: Int)
}

const definition = Person("Nome", 1)

/// Tests all public functions on their "happy path"
pub fn full_cicle_test() {
  let assert Ok(table) = database.create_table(definition, 0)

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
  let assert Error(Badarg) = database.create_table("Person", 0)
  let assert Error(Badarg) = database.create_table(1234, 0)
  let assert Error(Badarg) = database.create_table(False, 0)
  let assert Error(Badarg) = database.create_table(Person, 0)
  let sample = Person("Socrates", 7)
  let assert Error(IndexOutOfBounds) = database.create_table(sample, -1)
  let assert Error(IndexOutOfBounds) = database.create_table(sample, 2)
  let assert Ok(t) = database.create_table(sample, 0)

  let assert Ok(_) = database.drop_table(t)
}

pub fn direct_operations_test() {
  let assert Ok(table) = database.create_table(definition:, index_at: 0)
  let assert Ok(_) =
    database.transaction(table, database.insert(_, Person("Your mom™", 2048)))
  let assert Ok(Some(Person("Your mom™", 2048))) =
    database.transaction(table, database.find(_, "Your mom™"))
}
