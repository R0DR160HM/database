import database
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/int
import gleam/option.{None, Some}
import gleam/string
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

/// Tests all public functions on their "happy path"
pub fn full_cicle_test() {
  let assert Ok(table) = database.create_table("people", decoder())

  let piastri_id =
    crypto.strong_random_bytes(16) |> bit_array.base64_url_encode(False)

  let assert Ok([vettel_id, _verstappen_id]) =
    database.transaction(table, fn(ref) {
      let assert Ok(vettel_id) =
        database.insert(ref, Person("Sebastian Vettel", 87))
      let assert Ok(verstappen_id) =
        database.insert(ref, Person("Max Verstappen", 29))
      [vettel_id, verstappen_id]
    })

  let _ =
    database.transaction(table, fn(ref) {
      let assert None = database.find(ref, piastri_id)
      let assert Some(Person("Sebastian Vettel", 87)) =
        database.find(ref, vettel_id)
      let assert Ok(Nil) = database.delete(ref, vettel_id)
      let assert None = database.find(ref, vettel_id)
    })

  let assert Ok(_) = database.drop_table(table)
}

pub fn direct_operations_test() {
  let assert Ok(table) =
    database.create_table(name: "people", decode_with: decoder())
  let assert Ok(Ok(mom_id)) =
    database.transaction(table, database.insert(_, Person("Your mom™", 2048)))
  let assert Ok(Some(Person("Your mom™", 2048))) =
    database.transaction(table, database.find(_, mom_id))
  let assert Ok(_) = database.drop_table(table)
}

pub fn select_test() {
  let assert Ok(table) = database.create_table("people", decoder())

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
          #(_, Person("João", _)) -> database.Continue(value)
          #(_, Person(_, 55)) -> database.Continue(value)
          _ -> database.Skip
        }
      })
    })

  let assert Ok([#(_, Person("João", 23))]) =
    database.transaction(table, fn(ref) {
      database.select(ref, fn(value) {
        case value {
          #(_, Person("João", _)) -> database.Done(value)
          _ -> database.Skip
        }
      })
    })

  database.drop_table(table)
}

pub fn full_cicle_with_string_test() {
  let assert Ok(table) = database.create_table("testsss", decode.string)

  let _ = database.transaction(table, database.insert(_, "brbr patapim"))
  let assert Ok([id]) =
    database.transaction(table, fn(ref) {
      use value <- database.select(ref)
      case value {
        #(id, "brbr patapim") -> database.Done(id)
        _ -> database.Skip
      }
    })

  let assert Ok(option.Some("brbr patapim")) =
    database.transaction(table, database.find(_, id))

  let assert Ok(Ok(Nil)) = database.transaction(table, database.delete(_, id))

  let assert Ok(option.None) = database.transaction(table, database.find(_, id))

  let assert Ok(Nil) = database.drop_table(table)
}

pub fn migration_test() {
  let assert Ok(table) = database.create_table("people", decode.string)
  let assert Ok(_) = {
    use transac <- database.transaction(table)
    let _ = database.insert(transac, "Aristotle, 22")
    let _ = database.insert(transac, "Plato, 42")
    let _ = database.insert(transac, "Socrates, 23")
    let _ = database.insert(transac, "Aquinas, the GOAT")
  }

  let assert Ok(table) = database.create_table("people", decoder())

  let string_to_person_decoder = {
    use decoded_string <- decode.then(decode.string)
    case string.split(decoded_string, ", ") {
      [name, age] ->
        case int.parse(age) {
          Ok(age) -> decode.success(Person(name, age))
          _ -> decode.failure(Person("", 0), "int")
        }
      _ -> decode.failure(Person("", 0), "Name, age")
    }
  }
  let assert Ok(_) = {
    use value <- database.migrate(table)
    case decode.run(value, string_to_person_decoder) {
      Ok(person) -> database.Update(person)
      _ -> database.Delete
    }
  }

  // length 3 because Aquinas was not migrated
  let assert Ok([_, _, _]) = {
    use transac <- database.transaction(table)
    use #(_id, person) <- database.select(transac)
    case person {
      Person("Aristotle", 22) -> database.Continue(person)
      Person("Plato", 42) -> database.Continue(person)
      Person("Socrates", 23) -> database.Continue(person)
      Person("Aquinas", _) -> database.Continue(person)
      _ -> database.Skip
    }
  }

  let assert Ok(Nil) = database.drop_table(table)
}

pub fn update_test() {
  let assert Ok(table) = database.create_table("people", decoder())
  let assert Ok(Ok(id)) = {
    use transac <- database.transaction(table)
    database.insert(transac, Person("Rony Weasley", 11))
  }
  let assert Ok(_) = {
    use transac <- database.transaction(table)
    database.update(transac, id, Person("Percy Weasley", 14))
  }

  let assert Ok(Error(Nil)) = {
    use transac <- database.transaction(table)
    database.update(transac, "wrong_id", Person("Gina Weasley", 10))
  }

  let assert Ok(Some(Person("Percy Weasley", 14))) = {
    use transac <- database.transaction(table)
    database.find(transac, id)
  }

  let assert Ok([Person("Percy Weasley", 14)]) = {
    use transac <- database.transaction(table)
    use value <- database.select(transac)
    database.Continue(value.1)
  }

  let assert Ok(Nil) = database.drop_table(table)
}

pub type Animal {
  Dog
  Cat
  Parrot
}

pub type Pet {
  Pet(name: String, animal: Animal)
}

pub fn enum_test() {
  let pet_decoder = {
    use name <- database.field(0, decode.string)
    use animal <- database.field(1, database.enum([Dog, Cat, Parrot], Dog))
    decode.success(Pet(name:, animal:))
  }
  let assert Ok(table) = database.create_table("pets", pet_decoder)

  let assert Ok([dog_id, cat_id, parrot_id]) = {
    use transac <- database.transaction(table)
    let assert Ok(dog_id) = database.insert(transac, Pet("Bob", Dog))
    let assert Ok(cat_id) = database.insert(transac, Pet("Alice", Cat))
    let assert Ok(parrot_id) = database.insert(transac, Pet("Charlie", Parrot))
    [dog_id, cat_id, parrot_id]
  }

  let assert Ok(_) = {
    use transac <- database.transaction(table)
    let assert Some(Pet("Bob", Dog)) = database.find(transac, dog_id)
    let assert Some(Pet("Alice", Cat)) = database.find(transac, cat_id)
    let assert Some(Pet("Charlie", Parrot)) = database.find(transac, parrot_id)
  }

  let assert Ok(Nil) = database.drop_table(table)
}
