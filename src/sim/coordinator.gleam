import engine/supervisor as engine
import gleam/dict
import gleam/erlang/process.{Normal, send, try_call, type Subject}
import gleam/option.{None, Some, type Option}
import gleam/otp/actor
import gleam/string
import sim/metrics_logger

/// Simulator coordinator orchestrates client actors and aggregates metrics
/// for load test runs.
pub type Message {
  Configure(SimulationConfig, Subject(Result(Nil, CoordinatorError)))
  RegisterClient(
    ClientRegistration,
    Subject(Result(ClientHandle, CoordinatorError)),
  )
  RecordSample(source: String, sample: MetricSample)
  Snapshot(Subject(SimulationSnapshot))
  Shutdown
}

pub type CoordinatorError {
  AlreadyConfigured
  NotConfigured
  InvalidRegistration
}

pub type SimulationConfig {
  SimulationConfig(
    target_clients: Int,
    tick_interval_ms: Int,
    seed: Int,
  )
}

pub type ClientRegistration {
  ClientRegistration(label: String)
}

pub type ClientHandle {
  ClientHandle(id: Int, label: String)
}

pub type MetricSample {
  OperationRecorded(kind: String)
  EventRecorded(kind: String)
}

pub type Metrics {
  Metrics(operations: Int, events: Int)
}

pub type SimulationSnapshot {
  SimulationSnapshot(
    config: Option(SimulationConfig),
    client_count: Int,
    metrics: Metrics,
  )
}

pub fn start(engine_services: engine.Services) -> Result(Subject(Message), actor.StartError) {
  start_with(engine_services, None)
}

pub fn start_with(
  engine_services: engine.Services,
  logger: Option(Subject(metrics_logger.Message)),
) -> Result(Subject(Message), actor.StartError) {
  actor.start(
    State(
      engine: engine_services,
      config: None,
      clients: dict.new(),
      next_client_id: 1,
      metrics: Metrics(operations: 0, events: 0),
      metrics_logger: logger,
    ),
    handle_message,
  )
}

type State {
  State(
    engine: engine.Services,
    config: Option(SimulationConfig),
    clients: dict.Dict(Int, ClientHandle),
    next_client_id: Int,
    metrics: Metrics,
    metrics_logger: Option(Subject(metrics_logger.Message)),
  )
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    Configure(config, reply) -> configure(config, reply, state)
    RegisterClient(registration, reply) -> register_client(registration, reply, state)
    RecordSample(source: source, sample: sample) ->
      actor.continue(record_sample(source, sample, state))
    Snapshot(reply) -> snapshot(reply, state)
    Shutdown -> {
      maybe_flush_logger(state)
      actor.Stop(Normal)
    }
  }
}

fn configure(
  config: SimulationConfig,
  reply: Subject(Result(Nil, CoordinatorError)),
  state: State,
) -> actor.Next(Message, State) {
  case state.config {
    Some(_) -> {
      send(reply, Error(AlreadyConfigured))
      actor.continue(state)
    }

    None -> {
      send(reply, Ok(Nil))
      actor.continue(State(
        engine: state.engine,
        config: Some(config),
        clients: state.clients,
        next_client_id: state.next_client_id,
        metrics: state.metrics,
        metrics_logger: state.metrics_logger,
      ))
    }
  }
}

fn register_client(
  registration: ClientRegistration,
  reply: Subject(Result(ClientHandle, CoordinatorError)),
  state: State,
) -> actor.Next(Message, State) {
  case state.config {
    None -> {
      send(reply, Error(NotConfigured))
      actor.continue(state)
    }

    Some(_) ->
      case registration {
        ClientRegistration(label: label) ->
          case string.is_empty(label) {
            True -> {
              send(reply, Error(InvalidRegistration))
              actor.continue(state)
            }

            False -> {
              let handle = ClientHandle(id: state.next_client_id, label: label)
              let clients = dict.insert(state.clients, handle.id, handle)
              send(reply, Ok(handle))
              actor.continue(State(
                engine: state.engine,
                config: state.config,
                clients: clients,
                next_client_id: state.next_client_id + 1,
                metrics: state.metrics,
                metrics_logger: state.metrics_logger,
              ))
            }
          }
      }
  }
}

fn record_sample(source: String, sample: MetricSample, state: State) -> State {
  let metrics =
    case sample {
      OperationRecorded(_) ->
        Metrics(operations: state.metrics.operations + 1, events: state.metrics.events)
      EventRecorded(_) ->
        Metrics(operations: state.metrics.operations, events: state.metrics.events + 1)
    }
  maybe_log_sample(state.metrics_logger, source, sample)
  State(
    engine: state.engine,
    config: state.config,
    clients: state.clients,
    next_client_id: state.next_client_id,
    metrics: metrics,
    metrics_logger: state.metrics_logger,
  )
}

fn snapshot(
  reply: Subject(SimulationSnapshot),
  state: State,
) -> actor.Next(Message, State) {
  send(
    reply,
    SimulationSnapshot(
      config: state.config,
      client_count: dict.size(state.clients),
      metrics: state.metrics,
    ),
  )
  actor.continue(state)
}

fn maybe_log_sample(
  logger: Option(Subject(metrics_logger.Message)),
  source: String,
  sample: MetricSample,
) {
  case logger {
    Some(subject) -> send(subject, metrics_logger.Record(source: source, kind: metric_kind(sample)))
    None -> Nil
  }
}

fn maybe_flush_logger(state: State) {
  case state.metrics_logger {
    Some(subject) -> {
      let _ =
        try_call(subject, fn(responder) {
          metrics_logger.Flush(responder)
        }, 2000)
      Nil
    }
    None -> Nil
  }
}

fn metric_kind(sample: MetricSample) -> String {
  case sample {
    OperationRecorded(kind) -> kind
    EventRecorded(kind) -> kind
  }
}

