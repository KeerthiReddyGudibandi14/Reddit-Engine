# Distributed Reddit-Like Engine & Simulator (Part I)

## Team

1. Pragyna Abhishek Titty (UFID: 6419-2812)
2. Keerthi Reddy Gudibandi (UFID: 1365-2831)

This project implements the Part I engine and load simulator for a Reddit-style system entirely in Gleam, following a research-first design that emphasises OTP actors, typed message passing, and reproducible performance measurements. The deliverable is organised around two supervision trees:

- `engine`: registry actors for users and subreddits, a content coordinator for posts/comments/votes, and a direct-message router.
- `sim`: coordinator, metrics logger, and thousands of client actors that exercise the engine using configurable workloads.

## Prerequisites

- Gleam ≥ 1.2.1 and OTP ≥ 26 (tested locally on macOS 15). See the official Gleam installation guide.[^writing-gleam]

Install dependencies and compile artefacts:

```sh
gleam deps download
gleam build
```

## Running Tests

Unit and actor tests execute with:

```sh
gleam test
```

Tests cover pure scoring logic, the Zipf sampler, and OTP actors for all engine subsystems to guarantee message handling and state transitions remain deterministic before running large simulations.

## Running the Simulator

Launch a default simulation (10 clients × 30 ticks) and write metrics to `metrics.csv`:

```sh
gleam run
```

CLI flags tune workload shape:

- `--clients=<int>`: number of concurrent simulated users (default 10).
- `--ticks=<int>`: tick count per client session (default 30).
- `--home=<sub1,sub2>`: comma-separated initial subreddit memberships.
- `--post="Body"`: default text body for generated posts and comments.

Example 128-client sweep for 40 ticks:

```sh
gleam run -- --clients=128 --ticks=40 --home=general,technology,gaming
```

Each run appends per-event telemetry to `metrics.csv` and produces aggregate summaries under `metrics/` (see below).

## Architecture Overview

- **Engine Supervisor** (`src/engine/supervisor.gleam`): Boots user registry, subreddit registry, content coordinator, and DM router as OTP workers with typed subjects, enabling tree restarts on failure.[^gleam-otp]
- **Content Model** (`src/engine`): Strongly typed IDs, post/comment scoring, hierarchical comment trees, and karma accrual that mirrors Reddit semantics.[^reddit-api]
- **Simulator Supervisor** (`src/sim/supervisor.gleam`): Manages coordinator and metrics logger actors before spawning client processes that follow Zipf-distributed subreddit selections.[^zipf]
- **Zipf Sampler** (`src/sim/zipf.gleam`): Precomputes a discrete CDF for efficient sampling, validated by property tests ensuring total probability mass equals 1.0.
- **Metrics Logger** (`src/sim/metrics_logger.gleam`): Buffers CSV rows and honours backpressure by exposing synchronous `Flush`/`Shutdown` requests.

## Metrics & Reports

Scaling sweeps at 16/64/128 clients are stored in `metrics/summary.csv` with per-operation counts, throughput per client, and per-tick load. Raw chronological events remain in `metrics.csv`. A deeper analysis, methodology discussion, and result tables live in `docs/report.md`.

## Repository Layout

- `src/engine/`: Engine actors, types, and feed scoring utilities.
- `src/sim/`: Simulator coordinator, client behaviour policies, Zipf sampling, and metrics logging.
- `test/`: Gleeunit suites for pure logic modules and OTP actors.
- `metrics/`: Aggregated CSV outputs generated during scaling sweeps.
- `docs/`: Reports and supporting documentation.
