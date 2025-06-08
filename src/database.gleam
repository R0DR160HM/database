import gleam/erlang/atom.{type Atom}
import gleam/erlang/charlist

// BEAM interaction

type Storage {
  Set
}

type TableAttributes {
  File(charlist.Charlist)
  Type(Storage)
  Keypos(Int)
}

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

pub opaque type Table(a) {
  Table(
    tabname: Atom,
    attributes: List(TableAttributes),
    path: charlist.Charlist,
  )
}

pub type TableError {
  Badarg
  UnableToOpen
  UnableToClose
}

pub fn create_table(
  sample sample: a,
  index_at keypos: Int,
) -> Result(Table(a), TableError) {
  case is_record(sample), keypos >= 0 {
    True, True ->
      case keypos + 2 > erlang_tuple_size(sample) {
        True -> Error(Badarg)
        False -> {
          let at = erlang_element(1, sample)
          let name = atom.to_string(at)
          let path = charlist.from_string(name <> ".dets")

          let att = [File(path), Type(Set), Keypos(keypos + 2)]
          // +2 because Erlang arrays start at 1 and the first value from our tuple will always be its atom

          case dets_open_file(at, att) {
            Ok(tab) -> {
              case dets_close(tab) {
                Error(_) -> Error(UnableToClose)
                _ -> Ok(Table(at, att, path))
              }
            }
            Error(_) -> Error(UnableToOpen)
          }
        }
      }
    _, _ -> Error(Badarg)
  }
}

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

pub fn insert(transac: TableRef(a), value: a) {
  case dets_insert(transac, value) {
    Error(reason) -> Error(reason)
    _ -> Ok(Nil)
  }
}

pub fn delete(transac: TableRef(a), index: b) {
  case dets_delete(transac, index) {
    Error(reason) -> Error(reason)
    _ -> Ok(Nil)
  }
}

pub fn find(transac: TableRef(a), index: b) -> Result(a, Nil) {
  case dets_lookup(transac, index) {
    [resp] -> Ok(resp)
    _ -> Error(Nil)
  }
}

pub fn drop_table(table: Table(a)) {
  case file_delete(table.path) {
    Error(reason) -> Error(reason)
    _ -> Ok(Nil)
  }
}

fn is_record(value: a) {
  erlang_is_tuple(value) && erlang_is_atom(erlang_element(1, value))
}
