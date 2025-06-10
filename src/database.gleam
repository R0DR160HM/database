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

import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom.{type Atom}
import gleam/erlang/charlist
import gleam/option

// BEAM interaction

type Storage {
  Set
}

type TableAttributes {
  File(charlist.Charlist)
  Type(Storage)
  Keypos(Int)
}

type TableRef(a)

/// A reference to an open table, required to interact with said table.
/// Obtained through the `transaction(Table)` function
pub opaque type Transaction(a) {
  Transaction(ref: TableRef(a), decoder: decode.Decoder(a))
}

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
fn dets_lookup(tab: TableRef(a), index: b) -> List(dynamic.Dynamic)

@external(erlang, "dets", "traverse")
fn dets_traverse(
  tab: TableRef(a),
  select_fn: fn(dynamic.Dynamic) -> SelectOption(b),
) -> List(b)

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

// Lying about the type ouput here is the only
// way to ensure type-safety on the `select` function
@external(erlang, "erlang", "binary_to_atom")
fn erlang_binary_to_atom(value: String) -> SelectOption(a)

// Type-safe API

/// A collection of values used to access a DETS table.
pub opaque type Table(a) {
  Table(
    tabname: Atom,
    attributes: List(TableAttributes),
    path: charlist.Charlist,
    decoder: decode.Decoder(a),
  )
}

/// Possible error that may occur when using the library.
pub type TableError {
  /// The definition provided is not a Gleam record 
  Badarg

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
///   let table_def = Pet(name: "Pluto", animal: Dog)
///   let decoder = {
///     use name <- database.field(0, decode.string)
///     use animal <- database.field(1, my_animal_decoder)
///     decode.success(Pet(name:, animal:))
///   }
///   database.create_table(definition: table_def, decode_with: decoder)
///   // -> Ok(Table(Pet))
/// }
/// ```
///
pub fn create_table(
  definition definition: a,
  decode_with decoder: decode.Decoder(a),
) -> Result(Table(a), TableError) {
  case is_record(definition) {
    True ->
      case erlang_tuple_size(definition) < 2 {
        True -> Error(Badarg)
        False -> {
          let name_atom = erlang_element(1, definition)
          let name = atom.to_string(name_atom)

          let path = charlist.from_string(name <> ".dets")

          let att = [File(path), Type(Set), Keypos(2)]
          // 2 because Erlang arrays start at 1 and the first value from our tuple will always be its atom

          case dets_open_file(name_atom, att) {
            Ok(tab) -> {
              case dets_close(tab) {
                Error(_) -> Error(UnableToClose)
                _ -> Ok(Table(name_atom, att, path, decoder))
              }
            }
            Error(_) -> Error(UnableToOpen)
          }
        }
      }
    False -> Error(Badarg)
  }
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
  procedure: fn(Transaction(a)) -> b,
) -> Result(b, TableError) {
  case dets_open_file(table.tabname, table.attributes) {
    Error(_) -> Error(UnableToOpen)
    Ok(ref) -> {
      let resp = procedure(Transaction(ref, table.decoder))
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
pub fn insert(transac: Transaction(a), value: a) {
  case dets_insert(transac.ref, value) {
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
pub fn delete(transac: Transaction(a), index: b) {
  case dets_delete(transac.ref, index) {
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
pub fn find(transac: Transaction(a), index: b) -> option.Option(a) {
  case dets_lookup(transac.ref, index) {
    [resp] ->
      case decode.run(resp, transac.decoder) {
        Ok(val) -> option.Some(val)
        _ -> option.None
      }
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

/// Operations to perform on a select query.
pub type SelectOption(value) {

  /// Ignores the current value.
  Skip

  /// Adds the value to the return list.
  Continue(value)

  /// Adds the value to the return list
  /// and immediately returns the query.
  Done(value)
}

/// Searches for somethig on the table.
///
/// # Example
/// 
/// ```gleam
/// pub fn fetch_all_parrots(table: Table(Pet)) {
///   use ref <- database.transaction(table)
///   use value <- database.select(ref)
///   case value {
///     Pet(_name, Parrot) -> Continue(value)
///     _ -> Skip
///   }
/// }
/// ```
///
/// # IMPORTANT
/// **DETS tables are not sorted in any deterministic way, so
/// never assume that the last value inserted will be the last
/// one on the table.**
///
pub fn select(
  transac: Transaction(a),
  select_fn: fn(a) -> SelectOption(b),
) -> List(b) {
  let continue = erlang_binary_to_atom("continue")
  let new_fn = fn(dyn_value) {
    case decode.run(dyn_value, transac.decoder) {
      Ok(value) ->
        case select_fn(value) {
          Skip -> continue
          res -> res
        }
      _ -> continue
    }
  }
  dets_traverse(transac.ref, new_fn)
}

/// Field decoder
/// 
/// # Example
/// 
/// ```gleam
/// let decoder = {
///   use name <- database.field(0, decode.string)
///   use animal <- database.field(1, my_animal_decoder)
///   decode.success(Pet(name:, animal:))
/// }
/// ```
///
pub fn field(
  field_index: Int,
  field_decoder: decode.Decoder(t),
  next: fn(t) -> decode.Decoder(final),
) {
  // +1 to avoid the atomic name at the start of the tuple
  decode.field(field_index + 1, field_decoder, next)
}
// Ad maiorem Dei gloriam
