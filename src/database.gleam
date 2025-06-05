import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/node
import gleam/list
import gleam/result

// BEAM interaction

type Storage {
  Set
}

type TableAttributes {
  File(String)
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
fn dets_lookup(tab: TableRef(a), index: b) -> Result(List(a), c)

@external(erlang, "file", "delete")
fn file_delete(path: String) -> a

@external(erlang, "erlang", "element")
fn erlang_element(index: Int, tuple: a) -> Atom

// Type-safe API

pub opaque type Table(a) {
  Table(tabname: Atom, attributes: List(TableAttributes), path: String)
}

pub fn create_table(
  sample sample: a,
  index_at keypos: Int,
) -> Result(Table(a), reason) {
  let at = erlang_element(1, sample)
  let name = atom.to_string(at)
  let path = "storage/" <> name <> ".dets"

  let att = [File(path), Type(Set), Keypos(keypos + 2)]
  // +2 because Erlang arrays start at 1 and the first value from our tuple will always be its atom

  case dets_open_file(at, att) {
    Ok(tab) -> {
      case dets_close(tab) {
        Error(reason) -> Error(reason)
        Ok(_) -> Ok(Table(at, att, path))
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
      dets_close(ref)
      |> result.replace(resp)
    }
  }
}

pub fn insert(transac: TableRef(a), value: a) {
  let _ = dets_insert(transac, value)
  Nil
}

pub fn delete(transac: TableRef(a), index: b) {
  let _ = dets_delete(transac, index)
  Nil
}

pub fn select(transac: TableRef(a), index: b) -> Result(a, Nil) {
  case dets_lookup(transac, index) {
    Ok([resp]) -> Ok(resp)
    _ -> Error(Nil)
  }
}

pub fn drop_table(table: Table(a)) {
  file_delete(table.path)
  Nil
}
