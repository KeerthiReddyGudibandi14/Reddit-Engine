import engine/supervisor as engine
import gleam/erlang/process.{type Subject, Abnormal, new_subject, receive_forever, send}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError, InitFailed}
import gleam/otp/supervisor
import sim/coordinator
import sim/metrics_logger

/// Supervisor for the simulator process tree (coordinator + future actors).
pub type Simulation {
  Simulation(supervisor: Subject(supervisor.Message), handles: Handles)
}

pub type Handles {
  Handles(
    coordinator: Subject(coordinator.Message),
    metrics_logger: Subject(metrics_logger.Message),
  )
}

pub fn start(engine_services: engine.Services) -> Result(Simulation, StartError) {
  let ack = new_subject()
  let builder = new_builder(ack)

  let metrics_spec =
    supervisor.worker(fn(_builder: Builder) { metrics_logger.start("metrics.csv") })
    |> supervisor.returning(with_metrics_logger)

  let coordinator_spec =
    supervisor.worker(fn(builder: Builder) {
      case builder.metrics_logger {
        Some(logger) -> coordinator.start_with(engine_services, Some(logger))
        None -> Error(InitFailed(Abnormal("metrics logger missing")))
      }
    })
    |> supervisor.returning(with_coordinator)

  let init = fn(children) {
    children
    |> supervisor.add(metrics_spec)
    |> supervisor.add(coordinator_spec)
  }

  case
    supervisor.start_spec(supervisor.Spec(
      argument: builder,
      init: init,
      max_frequency: 5,
      frequency_period: 10,
    ))
  {
    Ok(supervisor_subject) -> {
      let handles = receive_forever(ack)
      Ok(Simulation(supervisor: supervisor_subject, handles: handles))
    }

    Error(reason) -> Error(reason)
  }
}

type Builder {
  Builder(
    reply: Subject(Handles),
    coordinator: Option(Subject(coordinator.Message)),
    metrics_logger: Option(Subject(metrics_logger.Message)),
    ack_sent: Bool,
  )
}

fn new_builder(reply: Subject(Handles)) -> Builder {
  Builder(reply: reply, coordinator: None, metrics_logger: None, ack_sent: False)
}

fn with_coordinator(
  builder: Builder,
  coordinator: Subject(coordinator.Message),
) -> Builder {
  Builder(
    reply: builder.reply,
    coordinator: Some(coordinator),
    metrics_logger: builder.metrics_logger,
    ack_sent: builder.ack_sent,
  )
  |> maybe_emit_handles
}

fn with_metrics_logger(
  builder: Builder,
  logger: Subject(metrics_logger.Message),
) -> Builder {
  Builder(
    reply: builder.reply,
    coordinator: builder.coordinator,
    metrics_logger: Some(logger),
    ack_sent: builder.ack_sent,
  )
  |> maybe_emit_handles
}

fn maybe_emit_handles(builder: Builder) -> Builder {
  case builder {
    Builder(
      reply: reply,
      coordinator: Some(coord),
      metrics_logger: Some(logger),
      ack_sent: False,
    ) -> {
      send(reply, Handles(coordinator: coord, metrics_logger: logger))
      Builder(
        reply: reply,
        coordinator: Some(coord),
        metrics_logger: Some(logger),
        ack_sent: True,
      )
    }

    _ -> builder
  }
}

