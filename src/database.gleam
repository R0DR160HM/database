//// An outrageously simple set of functions to interact with the BEAM
//// ETS (Erlang Term Storage) and DETS (Disk-based ETS) API.
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
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom.{type Atom}
import gleam/erlang/charlist
import gleam/list
import gleam/result

// BEAM interaction

type TableAttributes {
  File(charlist.Charlist)
  Type(TableAttributes)
  Keypos(Int)
  Public
  Set
}

type Continue {
  Continue
}

type TableRef(a)

/// A reference to an open table, required to interact with said table.
/// Obtained through the `transaction(Table)` function
pub opaque type Transaction(a) {
  /// Needs a decoder because the structure of the type might have changed between runs
  DiskTransaction(ref: TableRef(#(String, a)), decoder: decode.Decoder(a))

  /// Since an ETS table only exists at runtime, the type validation is made by the compiler itself,
  /// therefore no decoding or validation is necessary.
  MemoryTransaction(table: TableRef(#(String, a)))
}

@external(erlang, "dets", "open_file")
fn dets_open_file(
  name: Atom,
  att: List(TableAttributes),
) -> Result(TableRef(a), reason)

@external(erlang, "ets", "new")
fn ets_new(name: Atom, att: List(TableAttributes)) -> TableRef(a)

@external(erlang, "dets", "close")
fn dets_close(tab: TableRef(a)) -> Result(b, c)

@external(erlang, "ets", "safe_fixtable")
fn ets_safe_fixtable(tab: TableRef(a), activate: Bool) -> Bool

@external(erlang, "dets", "insert")
fn dets_insert(tab: TableRef(a), value: a) -> Result(b, c)

@external(erlang, "ets", "insert")
fn ets_insert(tab: TableRef(a), valub: a) -> Bool

@external(erlang, "dets", "delete")
fn dets_delete(tab: TableRef(a), index: b) -> Result(b, c)

@external(erlang, "ets", "delete")
fn ets_delete_element(tab: TableRef(a), index: b) -> Bool

@external(erlang, "ets", "delete")
fn ets_delete_table(tab: TableRef(a)) -> Bool

@external(erlang, "dets", "lookup")
fn dets_lookup(tab: TableRef(a), index: b) -> List(#(String, dynamic.Dynamic))

@external(erlang, "ets", "lookup")
fn ets_lookup(tab: TableRef(a), index: b) -> List(a)

@external(erlang, "dets", "traverse")
fn dets_traverse(
  tab: TableRef(a),
  select_fn: fn(#(String, dynamic.Dynamic)) -> Continue,
) -> List(b)

@external(erlang, "database_ffi", "safe_dets_select")
fn dets_select(
  tab: TableRef(a),
  specs: List(s),
) -> Result(List(#(String, dynamic.Dynamic)), reason)

@external(erlang, "database_ffi", "format_select_pattern")
fn format_select_pattern(func: f) -> p

@external(erlang, "ets", "select")
fn ets_select(tab: TableRef(a), specs: List(s)) -> List(a)

@external(erlang, "file", "delete")
fn file_delete(path: charlist.Charlist) -> a

@external(erlang, "database_ffi", "compare")
fn ffi_compare(a: a, b: b) -> Bool

// Type-safe API

/// A collection of values used to access a DETS/ETS table.
pub opaque type Table(a) {
  DiskTable(
    tabname: Atom,
    attributes: List(TableAttributes),
    path: charlist.Charlist,
    decoder: decode.Decoder(a),
  )
  MemoryTable(TableRef(#(String, a)))
}

/// Possible error that may occur when using the DETS operations.
pub type FileError {
  /// A problem occurred when trying to open and lock 
  /// the .dets file.
  UnableToOpen

  /// A problem ocurred when trying to write into the
  /// .dets file and close it.
  UnableToClose
}

/// Error returned by the `find` function.
pub type FindError {
  /// No data with the given ID was found.
  NotFound

  /// The data was found, but it could not be decoded with
  /// the provided decoder.
  UnableToDecode(List(decode.DecodeError))
}

/// Creats a DETS table (on disk!).
///
/// If no .dets file exists for the provided definition, creates one.
/// Otherwise, just checks whether the file is accessible and not
/// corrupted.
///
/// # Example
///
/// ```gleam
/// pub fn start_database() {
///   let table_decoder = {
///     use name <- database.field(0, decode.string)
///     use animal <- database.field(1, my_animal_decoder)
///     decode.success(Pet(name:, animal:))
///   }
///   let table_name = atom.create("pets")
///   database.create_dets_table(name: table_name, decode_with: table_decoder)
///   // -> Ok(Table(Pet))
/// }
/// ```
///
pub fn create_dets_table(
  name name: Atom,
  decode_with decoder: decode.Decoder(a),
) -> Result(Table(a), FileError) {
  let path = charlist.from_string(atom.to_string(name) <> ".dets")

  let att = [File(path), Type(Set), Keypos(1)]

  case dets_open_file(name, att) {
    Ok(tab) -> {
      case dets_close(tab) {
        Error(_) -> Error(UnableToClose)
        _ -> Ok(DiskTable(name, att, path, decoder))
      }
    }
    Error(_) -> Error(UnableToOpen)
  }
}

@deprecated("Use create_dets_table instead")
pub fn create_table(
  name name: Atom,
  decode_with decoder: decode.Decoder(a),
) -> Result(Table(a), FileError) {
  create_dets_table(name, decoder)
}

/// Creats a ETS table (in memory!).
///
/// # Example
///
/// ```gleam
/// pub fn start_database() {
///   let table_name = atom.create("pets")
///   database.create_ets_table(name: table_name)
///   // -> Table(a)
/// }
/// ```
///
pub fn create_ets_table(name name: Atom) -> Table(a) {
  let att = [Set, Public, Keypos(1)]
  MemoryTable(ets_new(name, att))
}

/// Errors that can happen during a `transaction()` call
pub type TransactionError(detail) {
  /// Errors related to the file (exclusive to the DETS tables)
  FileError(FileError)
  /// Errors that happened within the operation, and not on the transaction itself
  Operation(detail)
}

/// Allows you to interact with the table.
///
/// For DETS tables, it opens and locks the .dets file, then execute your operations.
/// Once the operations are done, it writes the changes into the file,
/// closes and releases it.
/// For ETS tables, it freezes the content of the table, then execute your operations.
/// Once the operations are done, it pushes the possible new changes (from other parts of your code)
/// into it and releases it.
///
/// # Example
///
/// ```gleam
/// pub fn is_pet_registered(table: Table(Pet), pet_id: String) {
///   use ref <- database.transaction(table)
///   case database.find(ref, pet_id) {
///     Ok(_) -> True
///     Error(_) -> False
///   }
/// }
/// ```
///
pub fn transaction(
  table: Table(a),
  procedure: fn(Transaction(a)) -> Result(b, c),
) -> Result(b, TransactionError(c)) {
  case table {
    DiskTable(tabname, attributes, _, _) ->
      case dets_open_file(tabname, attributes) {
        Error(_) -> Error(FileError(UnableToOpen))
        Ok(ref) -> {
          let resp = procedure(DiskTransaction(ref, table.decoder))
          case dets_close(ref) {
            Error(_) -> Error(FileError(UnableToClose))
            _ -> result.map_error(resp, Operation)
          }
        }
      }
    MemoryTable(ref) -> {
      ets_safe_fixtable(ref, True)
      let resp = procedure(MemoryTransaction(ref))
      ets_safe_fixtable(ref, False)
      result.map_error(resp, Operation)
    }
  }
}

/// Inserts a value into a table and return their generated id.
///
/// # Example
///
/// ```gleam
/// pub fn new_pet(table: Table(Pet), animal: Animal, name: String) {
///   let pet = Pet(name, animal)
///   use ref <- database.transaction(table)
///   database.insert(ref, pet)  
/// }
/// ```
///
pub fn insert(transac: Transaction(a), value: a) -> Result(String, Nil) {
  let id = crypto.strong_random_bytes(16) |> bit_array.base64_url_encode(False)
  upsert(transac, id, value)
}

/// Inserts a value into a table with a specific id. If the id already exists, the value is overwritten.
///
/// # Example
/// ```gleam
/// pub fn save_user(table: Table(User), user: User) {
///   use ref <- database.transaction(table)
///   database.upsert(ref, user.email, user)
/// }
/// ```
///
pub fn upsert(
  transac: Transaction(a),
  id: String,
  value: a,
) -> Result(String, Nil) {
  case transac {
    DiskTransaction(ref, _) ->
      case dets_insert(ref, #(id, value)) {
        Error(_) -> Error(Nil)
        _ -> Ok(id)
      }
    MemoryTransaction(ref) ->
      case ets_insert(ref, #(id, value)) {
        False -> Error(Nil)
        True -> Ok(id)
      }
  }
}

/// Updates a value in a table.
///
/// # Example
///
/// ```gleam
/// pub fn rename_pet(table: Table(Pet) id: String, pet: Pet, new_name: String) {
///   use transac <- database.transaction(table)
///   let pet = Pet(new_name, pet.animal)
///   database.update(transac, id, pet)
/// }
/// ```
///
pub fn update(
  transac: Transaction(a),
  id: String,
  value: a,
) -> Result(String, Nil) {
  case transac {
    DiskTransaction(ref, _) ->
      case dets_lookup(ref, id) {
        [_] -> upsert(transac, id, value)
        _ -> Error(Nil)
      }
    MemoryTransaction(ref) ->
      case ets_lookup(ref, id) {
        [_] -> upsert(transac, id, value)
        _ -> Error(Nil)
      }
  }
}

/// Deletes a value from a table.
///
/// # Example
///
/// ```gleam
/// pub fn delete_pet(table: Table(Pet) pet_id: String) {
///   use ref <- database.transaction(table)
///   database.delete(ref, pet_id)
/// }
/// ```
///
pub fn delete(transac: Transaction(a), id: String) -> Result(Nil, Nil) {
  case transac {
    DiskTransaction(ref, _) ->
      case dets_delete(ref, id) {
        Error(_) -> Error(Nil)
        _ -> Ok(Nil)
      }
    MemoryTransaction(ref) ->
      case ets_delete_element(ref, id) {
        False -> Error(Nil)
        True -> Ok(Nil)
      }
  }
}

/// Finds a value by its index
///
/// # Example
///
/// ```gleam
/// pub fn play_with_pluto(table: Table(Pet)) {
///   use ref <- database.transaction(table)
///   let resp = database.find(ref, known_pluto_id)
///   case resp {
///     Error(_) -> Error(PlutoNotFoundBlameTheAstronomers)
///     Ok(pluto) -> Ok(play_with(pluto))
///   }
/// }
/// ```
///
pub fn find(transac: Transaction(a), id: String) -> Result(a, FindError) {
  case transac {
    DiskTransaction(ref, decoder) ->
      case dets_lookup(ref, id) {
        [#(_, resp)] ->
          case decode.run(resp, decoder) {
            Ok(val) -> Ok(val)
            Error(errors) -> Error(UnableToDecode(errors))
          }
        _ -> Error(NotFound)
      }
    MemoryTransaction(ref) ->
      case ets_lookup(ref, id) {
        [#(_, val)] -> Ok(val)
        _ -> Error(NotFound)
      }
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
pub fn drop_table(table: Table(a)) -> Result(Nil, Nil) {
  case table {
    DiskTable(_, _, path, _) ->
      case file_delete(path) {
        Error(_) -> Error(Nil)
        _ -> Ok(Nil)
      }
    MemoryTable(ref) ->
      case ets_delete_table(ref) {
        False -> Error(Nil)
        True -> Ok(Nil)
      }
  }
}

/// Errors that can happen on a `select()`
pub type SelectError {
  /// The pattern provided is invalid
  Badarg
}

/// Searches for somethig on the table.
///
/// The native functions used to select values from tables (`ets|dets:select|match_object`)
/// rely on Erlang's extremely loose type system, which goes against both Gleam's and this projects's principles.
/// So, in order to make it functional (and performatic), some compromises had to be done.
/// Most notably, this function receives an untyped (unused generic) parameter, which is a tuple with the patterns to be matched,
/// said patterns can be values to be pattern-matched or functions that return said values, as shown below.
/// For more examples, access the `database_test.gleam` file
///
/// Don't worry, while the parameters for the result might be a bit loosey, its return is perfectly type safe,
/// as enforced by the Gleam compiler (on both ETS and DETS modes) and the `decode` API (only in DETS mode)
///
/// # Example
/// 
/// ```gleam
/// pub fn fetch_all_parrots(table: Table(Pet)) {
///   use ref <- database.transaction(table)
///   let _ = database.insert(ref, Parrot("Kiwi"))
///   let _ = database.insert(ref, Cat("Hulu"))
///   let _ = database.insert(ref, Parrot("Tata"))
///   let _ = database.insert(ref, Dog("Mina"))
///   database.select(ref, #(Parrot(_)))
/// }
/// ```
///
/// # IMPORTANT
/// **By default, DETS and ETS tables are not sorted in any deterministic way, so
/// never assume that the last value inserted will be the last
/// one on the table.**
///
pub fn select(
  transac: Transaction(a),
  patterns: tuple,
) -> Result(List(#(String, a)), SelectError) {
  case format_select_pattern(patterns) {
    Error(_) -> Error(Badarg)
    Ok(patterns) -> {
      case transac {
        MemoryTransaction(ref) -> Ok(ets_select(ref, patterns))
        DiskTransaction(ref, decoder) ->
          case dets_select(ref, patterns) {
            Error(_) -> Ok([])
            Ok(dyn_values) ->
              Ok(
                list.filter_map(dyn_values, fn(tpl) {
                  let #(id, dyn_value) = tpl
                  case decode.run(dyn_value, decoder) {
                    Ok(value) -> Ok(#(id, value))
                    Error(_) -> Error(Nil)
                  }
                }),
              )
          }
      }
    }
  }
}

/// Operations to perform on a migration.
pub type MigrateOptions(a) {

  /// Replaces the previous value with the new one.
  Update(a)

  /// Maintains the value as it currently is.
  ///
  /// Keep in mind that if the value does not conform
  /// to the provided decoder, it will be unaccessible
  /// for both `find` and `select` functions.
  /// Only remaining stored for future migrations.
  Keep

  /// Removes the value from the table.
  Delete
}

/// Migrates an DETS table to a new structure (does nothing to ETS tables, since those only exist in runtime).
/// When the type stored in the table changes, this function
/// allows you to update the table to the new structure.
/// 
/// This function will error if you try to use it on an ETS table.
///
/// # Example
///
/// ```gleam
/// pub fn migrate_pets(table: Table(Pet)) {
///   use value <- database.migrate(table)
///   case decode.run(value, my_pet_decoder()) {
///     Ok(pet) -> Update(pet)
///     _ -> Delete
///   } 
/// }
/// ```
/// 
pub fn migrate_dets(
  transac: Transaction(a),
  migration: fn(dynamic.Dynamic) -> MigrateOptions(a),
) -> Result(Nil, Nil) {
  case transac {
    MemoryTransaction(_) -> Error(Nil)
    DiskTransaction(ref, _) -> {
      let func = fn(tab_value) {
        let #(id, dyn_value) = tab_value
        case migration(dyn_value) {
          Update(new_value) -> {
            let _ = dets_insert(ref, #(id, new_value))
            Continue
          }
          Delete -> {
            let _ = dets_delete(ref, id)
            Continue
          }
          Keep -> Continue
        }
      }
      let _ = dets_traverse(ref, func)
      Ok(Nil)
    }
  }
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

/// Enum decoder
/// 
/// # Example
/// 
/// ```gleam
/// let decoder = {
///   use name <- database.field(0, decode.string)
///   use animal <- database.field(1, database.enum([Dog, Cat, Parrot], Dog))
///   decode.success(Pet(name:, animal:))
/// }
/// ```
///
pub fn enum(values: List(a), zero_value: a) {
  use data <- decode.new_primitive_decoder("Enum")
  case list.find(values, ffi_compare(_, data)) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(zero_value)
  }
}
// Ad maiorem Dei gloriam
