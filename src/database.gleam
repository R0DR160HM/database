import gleam/list
import gleam/dynamic/decode
import gleam/erlang/node
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}

// BEAM interaction

type TransactionResponse(a) {
    Atomic(a)
    Aborted(a)
}

type Attributes {
    Attributes(List(Atom))
}

type AlreadyExists(a) {
    AlreadyExists(a)
}

@external(erlang, "mnesia", "create_schema")
fn raw_create_schema(nodes: List(node.Node)) -> Dynamic

@external(erlang, "mnesia", "start")
fn raw_start() -> Result(a, b)

@external(erlang, "mnesia", "create_table")
fn raw_create_table(a: Atom, l: List(Attributes)) -> Dynamic

@external(erlang, "mnesia", "transaction")
fn raw_transaction(func: fn() -> a) -> TransactionResponse(a)

@external(erlang, "mnesia", "write")
fn raw_write(d: Dynamic) -> Atom

@external(erlang, "mnesia", "read")
fn raw_read(d: Dynamic) -> List(Dynamic)

@external(erlang, "mnesia", "stop")
fn raw_stop() -> Atom


@external(erlang, "erlang", "element")
fn erlang_element(at_index index: Int, in element: a) -> Dynamic

// Type-safe (hopefully) API

pub fn start() -> Result(Nil, reason) {
    let _ = raw_create_schema([node.self()]) // Error just means the schema is already created, so we can safely ignore it.
    case raw_start() {
        Ok(_) -> Ok(Nil)
        Error(b) -> Error(b)
    }
}

pub fn create_table(sample sample: a, with_labels labels: List(String)) {
    let at_table_name = erlang_element(1, sample) // Erlang arrays start a index 1
    |> atom.from_dynamic

    let at_labels = list.map(labels, fn (label) { atom.create_from_string(label) })
    raw_create_table(at_table_name, [Attributes(at_labels)])

}
