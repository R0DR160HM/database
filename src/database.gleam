//// An outrageously simple set of functions to interact with the BEAM
//// DETS (Disk-based Erlang Term Storage) API.
//// 
//// Good for small projects and POCs.
////
////
//// This project DOES NOT intend to serve as direct bindings to the 
//// DETS API, but rather to interact with it in a gleamy way:
////   1. with a simple and concise interface;
////   2. type-safely;
////   3. no unexpected crashes, all errors are values.

import gleam/bit_array
import gleam/crypto
import gleam/erlang/atom.{type Atom}
import gleam/erlang/charlist
import gleam/option
import gleam/string

// BEAM interaction

type Storage {
  Set
}

type TableAttributes {
  File(charlist.Charlist)
  Type(Storage)
  Keypos(Int)
}

/// A reference to an open table, required to interact with said table.
/// Obtained through the `transaction(Table)` function
pub type TableRef(a)

@external(erlang, "dets", "open_file")
fn dets_open_file(
  name: Atom,
  att: List(TableAttributes),
) -> Result(TableRef(a), reason)

@external(erlang, "dets", "close")
fn dets_close(tab: TableRef(a)) -> Result(b, c)

@external(erlang, "dets", "insert")
fn dets_insert(tab: TableRef(a), value: a) -> Result(b, c)

@external(erlang, "dets", "delete")
fn dets_delete(tab: TableRef(a), index: b) -> Result(b, c)

@external(erlang, "dets", "lookup")
fn dets_lookup(tab: TableRef(a), index: b) -> List(a)

@external(erlang, "file", "delete")
fn file_delete(path: charlist.Charlist) -> a

@external(erlang, "erlang", "element")
fn erlang_element(index: Int, tuple: a) -> Atom

@external(erlang, "erlang", "is_tuple")
fn erlang_is_tuple(tuple: a) -> Bool

@external(erlang, "erlang", "is_atom")
fn erlang_is_atom(atom: Atom) -> Bool

@external(erlang, "erlang", "tuple_size")
fn erlang_tuple_size(tuple: a) -> Int

// Type-safe API

/// A collection of values used to access a DETS table.
pub opaque type Table(a) {
  Table(
    tabname: Atom,
    attributes: List(TableAttributes),
    path: charlist.Charlist,
  )
}

/// Possible error that may occur when using the library.
pub type TableError {
  /// The definition provided is not a Gleam record 
  Badarg

  /// The index provided for the primary_key is lower
  /// than 0 or higher than the record size
  IndexOutOfBounds

  /// A problem occurred when trying to open and lock 
  /// the .dets file.
  UnableToOpen

  /// A problem ocurred when trying to write into the
  /// .dets file and close it.
  UnableToClose
}

/// Creats a table.
///
/// ## Important
/// **THE TABLE IS ENTIRELY DEPENDENT ON THE DEFINITION PROVIDED,
/// ANY CHANGE TO DEFINITION - EVEN IF EVERYTHING REMAINS OF THE SAME
/// TYPE - WILL CAUSE ANOTHER TABLE TO BE CREATED.**
///
/// If no .dets file exists for the provided definition, creates one.
/// Otherwise, just checks whether the file is accessible and not
/// corrupted.
///
/// # Example
///
/// ```gleam
/// pub fn start_database() {
///   let pluto = Pet(name: "Pluto", animal: Dog)
///   database.create_table(definition: pluto, index_at: 0)
///   // -> Ok(Table(Pet))
/// }
/// ```
///
pub fn create_table(
  definition definition: a,
  index_at keypos: Int,
) -> Result(Table(a), TableError) {
  case is_record(definition), keypos >= 0 {
    True, True ->
      case keypos + 2 > erlang_tuple_size(definition) {
        True -> Error(IndexOutOfBounds)
        False -> {
          let original_atom = erlang_element(1, definition)
          let name =
            atom.to_string(original_atom)
            <> "_"
            <> generate_signature(definition)
          let new_atom = atom.create_from_string(name)

          let path = charlist.from_string(name <> ".dets")

          let att = [File(path), Type(Set), Keypos(keypos + 2)]
          // +2 because Erlang arrays start at 1 and the first value from our tuple will always be its atom

          case dets_open_file(new_atom, att) {
            Ok(tab) -> {
              case dets_close(tab) {
                Error(_) -> Error(UnableToClose)
                _ -> Ok(Table(new_atom, att, path))
              }
            }
            Error(_) -> Error(UnableToOpen)
          }
        }
      }
    False, _ -> Error(Badarg)
    _, False -> Error(IndexOutOfBounds)
  }
}

/// Ensures type-safety cryptographically
fn generate_signature(for value: a) {
  <<string.inspect(value):utf8>>
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base64_url_encode(False)
}

/// Allows you to interact with the table.
///
/// It opens and locks the .dets file, then execute your operations.
/// Once the operations are done, it writes the changes into the file,
/// closes and releases it.
///
/// # Example
///
/// ```gleam
/// pub fn is_pet_registered(table: Table(Pet), petname: String) {
///   use ref <- database.transaction(table)
///   case database.find(ref, petname) {
///     Some(_) -> True
///     None -> False
///   }
/// }
/// ```
///
pub fn transaction(
  table: Table(a),
  procedure: fn(TableRef(a)) -> b,
) -> Result(b, TableError) {
  case dets_open_file(table.tabname, table.attributes) {
    Error(_) -> Error(UnableToOpen)
    Ok(ref) -> {
      let resp = procedure(ref)
      case dets_close(ref) {
        Error(_) -> Error(UnableToClose)
        _ -> Ok(resp)
      }
    }
  }
}

/// Inserts a value into a table.
///
/// DETS tables do not have support for update, only for upsert.
/// So if you have to change a value, just insert a new value
/// with the same index, and it will replace the previous value.
///
/// # Example
///
/// ```gleam
/// pub fn new_pet(table: Table(Pet), animal: Animal, name: String) {
///   let pet = Pet(name, animal)
///   let op = database.transaction(table, fn(ref) {
///     database.insert(ref, pet)
///   })
///   case op {
///     Ok(_) -> Ok(pet)
///     Error(reason) -> Error(reason)
///   }
/// }
/// ```
///
pub fn insert(transac: TableRef(a), value: a) {
  case dets_insert(transac, value) {
    Error(reason) -> Error(reason)
    _ -> Ok(Nil)
  }
}

/// Deletes a value from a table.
///
/// # Example
///
/// ```gleam
/// pub fn delete_pet(table: Table(Pet) petname: String) {
///   use ref <- database.transaction(table)
///   database.delete(ref, petname)
/// }
/// ```
///
pub fn delete(transac: TableRef(a), index: b) {
  case dets_delete(transac, index) {
    Error(reason) -> Error(reason)
    _ -> Ok(Nil)
  }
}

/// Finds a value by its index
///
/// # Example
///
/// ```gleam
/// pub fn play_with_pluto(table: Table(Pet)) {
///   use ref <- database.transaction(table)
///   let resp = database.find(ref, "Pluto")
///   case resp {
///     None -> Error(PlutoNotFoundBlameTheAstronomers)
///     Some(pluto) -> Ok(play_with(pluto))
///   }
/// }
/// ```
///
pub fn find(transac: TableRef(a), index: b) -> option.Option(a) {
  case dets_lookup(transac, index) {
    [resp] -> option.Some(resp)
    _ -> option.None
  }
}

/// Deletes the entire table file
///
/// # Example
///
/// ```gleam
/// pub fn destroy_all_pets(table: Table(Pet), password: String) {
///   case password {
///     "Yes, I am evil." -> {
///       database.drop_table(table)
///       Ok(Nil)
///     }
///     _ -> Error(WrongPassword)
///   }
/// }
/// ```
///
pub fn drop_table(table: Table(a)) {
  case file_delete(table.path) {
    Error(reason) -> Error(reason)
    _ -> Ok(Nil)
  }
}

fn is_record(value: a) {
  erlang_is_tuple(value) && erlang_is_atom(erlang_element(1, value))
}
