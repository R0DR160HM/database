import gleam/erlang/atom.{type Atom}
import gleam/result
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

// Type-safe API

pub opaque type Table(a) {
  Table(tabname: Atom, attributes: List(TableAttributes), path: charlist.Charlist)
}

pub fn create_table(
  sample sample: a,
  index_at keypos: Int,
) -> Result(Table(a), reason) {
  let at = erlang_element(1, sample)
  let name = atom.to_string(at)
  let path = charlist.from_string(name <> ".dets")

  let att = [File(path), Type(Set), Keypos(keypos + 2)]
  // +2 because Erlang arrays start at 1 and the first value from our tuple will always be its atom

  case dets_open_file(at, att) {
    Ok(tab) -> {
      case dets_close(tab) {
        Error(reason) -> Error(reason)
        _ -> Ok(Table(at, att, path))
      }
    }
    Error(reason) -> Error(reason)
  }
}

pub fn transaction(
  table: Table(a),
  procedure: fn(TableRef(a)) -> b,
) -> Result(b, reason) {
  case dets_open_file(table.tabname, table.attributes) {
    Error(reason) -> Error(reason)
    Ok(ref) -> {
      let resp = procedure(ref)
      case dets_close(ref) {
        Error(reason) -> Error(reason)
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

