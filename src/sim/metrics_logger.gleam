import gleam/erlang.{Millisecond, system_time}
import gleam/erlang/atom
import gleam/erlang/process.{Normal, send, type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/string

@external(erlang, "file", "write_file")
fn erlang_write_file(
  path: String,
  data: String,
  options: List(atom.Atom),
) -> Result(Nil, atom.Atom)

pub type Message {
  Record(source: String, kind: String)
  Flush(Subject(Result(Nil, atom.Atom)))
  Shutdown(Subject(Result(Nil, atom.Atom)))
}

pub fn start(path: String) -> Result(Subject(Message), actor.StartError) {
  let _ = write_header(path)
  actor.start(
    State(path: path, buffer: [], header_written: True),
    handle_message,
  )
}

type MetricEntry {
  MetricEntry(timestamp: Int, source: String, kind: String)
}

type State {
  State(path: String, buffer: List(MetricEntry), header_written: Bool)
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    Record(source, kind) -> actor.continue(add_entry(state, source, kind))
    Flush(reply) -> flush(reply, state)
    Shutdown(reply) -> shutdown(reply, state)
  }
}

fn add_entry(state: State, source: String, kind: String) -> State {
  let entry = MetricEntry(timestamp: system_time(Millisecond), source: source, kind: kind)
  State(path: state.path, buffer: [entry, ..state.buffer], header_written: state.header_written)
}

fn flush(
  reply: Subject(Result(Nil, atom.Atom)),
  state: State,
) -> actor.Next(Message, State) {
  case flush_to_disk(state) {
    Ok(_) -> {
      send(reply, Ok(Nil))
      actor.continue(State(path: state.path, buffer: [], header_written: state.header_written))
    }

    Error(reason) -> {
      send(reply, Error(reason))
      actor.continue(state)
    }
  }
}

fn shutdown(
  reply: Subject(Result(Nil, atom.Atom)),
  state: State,
) -> actor.Next(Message, State) {
  let result = flush_to_disk(state)
  send(reply, result)
  actor.Stop(Normal)
}

fn flush_to_disk(state: State) -> Result(Nil, atom.Atom) {
  case list.reverse(state.buffer) {
    [] -> Ok(Nil)
    entries -> {
      let lines = entries |> list.map(format_entry)
      let csv_body = join_lines(lines) <> "\n"
      normalize_write_result(
        erlang_write_file(
          state.path,
          csv_body,
          [
            atom.create_from_string("append"),
            atom.create_from_string("binary"),
          ],
        ),
      )
    }
  }
}

fn write_header(path: String) -> Result(Nil, atom.Atom) {
  normalize_write_result(
    erlang_write_file(
      path,
      "timestamp,source,kind\n",
      [atom.create_from_string("write"), atom.create_from_string("binary")],
    ),
  )
}

fn normalize_write_result(result: Result(Nil, atom.Atom)) -> Result(Nil, atom.Atom) {
  case result {
    Error(reason) -> Error(reason)
    _ -> Ok(Nil)
  }
}

fn format_entry(entry: MetricEntry) -> String {
  string.concat([
    int.to_string(entry.timestamp),
    ",",
    escape(entry.source),
    ",",
    escape(entry.kind),
  ])
}

fn join_lines(lines: List(String)) -> String {
  list.fold(
    lines,
    "",
    fn(acc, line) {
      case acc {
        "" -> line
        _ -> string.concat([acc, "\n", line])
      }
    },
  )
}

fn escape(text: String) -> String {
  case string.contains(text, ",") {
    False -> text
    True -> string.concat(["\"", string.replace(text, "\"", "\"\""), "\""])
  }
}

