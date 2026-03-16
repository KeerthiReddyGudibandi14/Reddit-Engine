import engine/content_coordinator
import engine/dm_router
import engine/subreddit_registry
import engine/user_registry
import gleam/erlang/process.{
  type Subject, Abnormal, new_subject, receive_forever, send,
}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError, InitFailed}
import gleam/otp/supervisor

/// Supervisor wiring together engine subsystems (users, subreddits, content,
/// etc.) as independent actors. Based on
/// https://hexdocs.pm/gleam_otp/gleam/otp/supervisor.html
pub type Engine {
  Engine(supervisor: Subject(supervisor.Message), services: Services)
}

pub type Services {
  Services(
    user_registry: Subject(user_registry.Message),
    subreddit_registry: Subject(subreddit_registry.Message),
    content_coordinator: Subject(content_coordinator.Message),
    dm_router: Subject(dm_router.Message),
  )
}

pub fn start() -> Result(Engine, StartError) {
  let ack = new_subject()
  let builder = new_builder(ack)

  let user_spec =
    supervisor.worker(fn(_builder: Builder) { user_registry.start() })
    |> supervisor.returning(with_user_registry)

  let subreddit_spec =
    supervisor.worker(fn(builder: Builder) {
      case builder.user_registry {
        Some(user_reg) -> subreddit_registry.start(user_reg)
        None -> Error(InitFailed(Abnormal("user registry unavailable")))
      }
    })
    |> supervisor.returning(with_subreddit_registry)

  let content_spec =
    supervisor.worker(fn(builder: Builder) {
      case builder.user_registry, builder.subreddit_registry {
        Some(user_reg), Some(sub_reg) ->
          content_coordinator.start(user_reg, sub_reg)
        _, _ ->
          Error(
            InitFailed(Abnormal("content coordinator dependencies missing")),
          )
      }
    })
    |> supervisor.returning(with_content_coordinator)

  let dm_spec =
    supervisor.worker(fn(_builder: Builder) { dm_router.start() })
    |> supervisor.returning(with_dm_router)

  let init = fn(children) {
    children
    |> supervisor.add(user_spec)
    |> supervisor.add(subreddit_spec)
    |> supervisor.add(content_spec)
    |> supervisor.add(dm_spec)
  }

  case
    supervisor.start_spec(supervisor.Spec(
      argument: builder,
      init: init,
      max_frequency: 5,
      frequency_period: 10,
    ))
  {
    Ok(subject) -> {
      let services = receive_forever(ack)
      Ok(Engine(supervisor: subject, services: services))
    }

    Error(reason) -> Error(reason)
  }
}

type Builder {
  Builder(
    reply: Subject(Services),
    user_registry: Option(Subject(user_registry.Message)),
    subreddit_registry: Option(Subject(subreddit_registry.Message)),
    content_coordinator: Option(Subject(content_coordinator.Message)),
    dm_router: Option(Subject(dm_router.Message)),
    ack_sent: Bool,
  )
}

fn new_builder(reply: Subject(Services)) -> Builder {
  Builder(
    reply: reply,
    user_registry: None,
    subreddit_registry: None,
    content_coordinator: None,
    dm_router: None,
    ack_sent: False,
  )
}

fn with_user_registry(
  builder: Builder,
  registry: Subject(user_registry.Message),
) -> Builder {
  Builder(
    reply: builder.reply,
    user_registry: Some(registry),
    subreddit_registry: builder.subreddit_registry,
    content_coordinator: builder.content_coordinator,
    dm_router: builder.dm_router,
    ack_sent: builder.ack_sent,
  )
  |> maybe_emit_service_handles
}

fn with_subreddit_registry(
  builder: Builder,
  registry: Subject(subreddit_registry.Message),
) -> Builder {
  Builder(
    reply: builder.reply,
    user_registry: builder.user_registry,
    subreddit_registry: Some(registry),
    content_coordinator: builder.content_coordinator,
    dm_router: builder.dm_router,
    ack_sent: builder.ack_sent,
  )
  |> maybe_emit_service_handles
}

fn with_content_coordinator(
  builder: Builder,
  coordinator: Subject(content_coordinator.Message),
) -> Builder {
  Builder(
    reply: builder.reply,
    user_registry: builder.user_registry,
    subreddit_registry: builder.subreddit_registry,
    content_coordinator: Some(coordinator),
    dm_router: builder.dm_router,
    ack_sent: builder.ack_sent,
  )
  |> maybe_emit_service_handles
}

fn with_dm_router(
  builder: Builder,
  router: Subject(dm_router.Message),
) -> Builder {
  Builder(
    reply: builder.reply,
    user_registry: builder.user_registry,
    subreddit_registry: builder.subreddit_registry,
    content_coordinator: builder.content_coordinator,
    dm_router: Some(router),
    ack_sent: builder.ack_sent,
  )
  |> maybe_emit_service_handles
}

fn maybe_emit_service_handles(builder: Builder) -> Builder {
  case builder {
    Builder(
      reply: reply,
      user_registry: Some(user_reg),
      subreddit_registry: Some(sub_reg),
      content_coordinator: Some(content),
      dm_router: Some(dm),
      ack_sent: False,
    ) -> {
      send(
        reply,
        Services(
          user_registry: user_reg,
          subreddit_registry: sub_reg,
          content_coordinator: content,
          dm_router: dm,
        ),
      )
      Builder(
        reply: reply,
        user_registry: Some(user_reg),
        subreddit_registry: Some(sub_reg),
        content_coordinator: Some(content),
        dm_router: Some(dm),
        ack_sent: True,
      )
    }

    _ -> builder
  }
}
