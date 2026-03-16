import argv
import engine/supervisor
import gleam/erlang
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import sim/client
import sim/coordinator
import sim/metrics_logger
import sim/supervisor as sim_supervisor

pub fn main() -> Nil {
  let args = argv.load()
  let cli_config = parse_args(args.arguments)
  io.println(
    string.concat([
      "Starting simulation with ",
      int.to_string(cli_config.clients),
      " clients for ",
      int.to_string(cli_config.ticks),
      " ticks per client",
    ]),
  )
  run_simulation(cli_config)
}

type CliConfig {
  CliConfig(
    clients: Int,
    ticks: Int,
    home_subreddits: List(String),
    post_body: String,
  )
}

fn default_cli_config() -> CliConfig {
  CliConfig(
    clients: 10,
    ticks: 30,
    home_subreddits: ["general", "technology"],
    post_body: "Hello from Gleam simulation!",
  )
}

fn parse_args(args: List(String)) -> CliConfig {
  list.fold(args, default_cli_config(), parse_arg)
}

fn parse_arg(config: CliConfig, arg: String) -> CliConfig {
  case string.split_once(arg, on: "=") {
    Ok(#("--clients", value)) ->
      case int.parse(value) {
        Ok(parsed) -> CliConfig(..config, clients: int.max(parsed, 0))
        Error(_) -> config
      }

    Ok(#("--ticks", value)) ->
      case int.parse(value) {
        Ok(parsed) -> CliConfig(..config, ticks: int.max(parsed, 0))
        Error(_) -> config
      }

    Ok(#("--home", value)) ->
      CliConfig(..config, home_subreddits: parse_home_subreddits(value))

    Ok(#("--post", value)) -> CliConfig(..config, post_body: value)

    _ -> config
  }
}

fn parse_home_subreddits(value: String) -> List(String) {
  let subs =
    value
    |> string.split(on: ",")
    |> list.map(string.trim)
    |> list.filter(fn(name) { name != "" })

  case subs {
    [] -> ["general"]
    _ -> subs
  }
}

fn run_simulation(config: CliConfig) -> Nil {
  case supervisor.start() {
    Ok(supervisor.Engine(supervisor: _engine_supervisor, services: services)) ->
      case sim_supervisor.start(services) {
        Ok(sim_supervisor.Simulation(_sim_supervisor, handles)) -> {
          let simulation_config = coordinator.SimulationConfig(
            target_clients: config.clients,
            tick_interval_ms: 25,
            seed: int.absolute_value(erlang.system_time(erlang.Millisecond)),
          )

          case configure_coordinator(handles.coordinator, simulation_config) {
            Ok(Nil) -> {
              let client_subjects =
                start_clients(config, services, handles.coordinator)
              run_ticks(client_subjects, config.ticks)
              list.each(client_subjects, fn(subject) {
                process.send(subject, client.Shutdown)
              })
              process.sleep(300)
              case flush_metrics_logger(handles.metrics_logger) {
                Ok(_) -> Nil
                Error(message) -> io.println(string.concat(["Warning: ", message]))
              }
              report_snapshot(handles.coordinator)
              process.send(handles.coordinator, coordinator.Shutdown)
              process.sleep(100)
              io.println("Simulation complete. Metrics appended to metrics.csv")
            }

            Error(message) -> io.println(message)
          }
        }

        Error(_start_error) ->
          io.println("Failed to start simulator supervisor")
      }

    Error(_start_error) -> io.println("Failed to start engine supervisor")
  }
}

fn configure_coordinator(
  coordinator_subject: process.Subject(coordinator.Message),
  config: coordinator.SimulationConfig,
) -> Result(Nil, String) {
  case
    process.try_call(coordinator_subject, fn(responder) {
      coordinator.Configure(config, responder)
    }, 1000)
  {
    Ok(result) ->
      case result {
        Ok(_) -> Ok(Nil)
        Error(error) -> Error(coordinator_error_to_string(error))
      }

    Error(call_error) -> Error(call_error_to_string("configure coordinator", call_error))
  }
}

fn coordinator_error_to_string(error: coordinator.CoordinatorError) -> String {
  case error {
    coordinator.AlreadyConfigured -> "Coordinator already configured"
    coordinator.NotConfigured -> "Coordinator not configured"
    coordinator.InvalidRegistration -> "Invalid client registration"
  }
}

fn start_clients(
  config: CliConfig,
  engine_services: supervisor.Services,
  coordinator_subject: process.Subject(coordinator.Message),
) -> List(process.Subject(client.Message)) {
  let client_config = client.ClientConfig(
    username_prefix: "sim-user",
    home_subreddits: config.home_subreddits,
    post_body: config.post_body,
  )

  let client_ids =
    case config.clients <= 0 {
      True -> []
      False -> list.range(1, config.clients)
    }

  client_ids
  |> list.fold([], fn(acc, id) {
    let label = string.concat(["client-", int.to_string(id)])
    case register_client(coordinator_subject, label) {
      Ok(handle) ->
        case client.start(handle.id, handle.label, engine_services, coordinator_subject, client_config) {
          Ok(subject) -> {
            process.send(subject, client.Begin)
            [subject, ..acc]
          }

          Error(_) -> acc
        }

      Error(_) -> acc
    }
  })
  |> list.reverse
}

fn register_client(
  coordinator_subject: process.Subject(coordinator.Message),
  label: String,
) -> Result(coordinator.ClientHandle, String) {
  case
    process.try_call(coordinator_subject, fn(responder) {
      coordinator.RegisterClient(
        coordinator.ClientRegistration(label: label),
        responder,
      )
    }, 1000)
  {
    Ok(register_result) ->
      case register_result {
        Ok(handle) -> Ok(handle)
        Error(error) -> Error(coordinator_error_to_string(error))
      }

    Error(call_error) -> Error(call_error_to_string("register client", call_error))
  }
}

fn run_ticks(subjects: List(process.Subject(client.Message)), ticks: Int) -> Nil {
  case ticks <= 0 {
    True -> Nil
    False -> {
      list.each(subjects, fn(subject) {
        process.send(subject, client.Tick)
      })
      run_ticks(subjects, ticks - 1)
    }
  }
}

fn report_snapshot(coordinator_subject: process.Subject(coordinator.Message)) {
  case process.try_call(coordinator_subject, fn(responder) {
    coordinator.Snapshot(responder)
  }, 1000)
  {
    Ok(snapshot) -> print_snapshot(snapshot)
    Error(call_error) ->
      io.println(
        call_error_to_string("retrieve snapshot", call_error),
      )
  }
}

fn print_snapshot(snapshot: coordinator.SimulationSnapshot) -> Nil {
  io.println(
    string.concat([
      "Coordinator reports ",
      int.to_string(snapshot.client_count),
      " registered clients",
    ]),
  )
  io.println(
    string.concat([
      "Operations recorded: ",
      int.to_string(snapshot.metrics.operations),
    ]),
  )
  io.println(
    string.concat([
      "Events recorded: ",
      int.to_string(snapshot.metrics.events),
    ]),
  )
}

fn call_error_to_string(context: String, error: process.CallError(response)) -> String {
  case error {
    process.CalleeDown(_) ->
      string.concat(["Failed to ", context, ": coordinator process exited"])

    process.CallTimeout ->
      string.concat(["Failed to ", context, ": call timed out"])
  }
}

fn flush_metrics_logger(
  logger: process.Subject(metrics_logger.Message),
) -> Result(Nil, String) {
  case
    process.try_call(logger, fn(responder) {
      metrics_logger.Flush(responder)
    }, 2000)
  {
    Ok(result) ->
      case result {
        Ok(_) -> Ok(Nil)
        Error(reason) -> Error(metrics_file_error("flush metrics logger", reason))
      }

    Error(call_error) -> Error(call_error_to_string("flush metrics logger", call_error))
  }
}

fn metrics_file_error(context: String, reason: atom.Atom) -> String {
  string.concat([
    "Failed to ",
    context,
    ": ",
    atom.to_string(reason),
  ])
}
