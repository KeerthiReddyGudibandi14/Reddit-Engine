# Reddit Engine

A Reddit-like distributed backend system implemented in Gleam on the Erlang VM using the actor model. The project simulates the core functionality of Reddit while demonstrating scalable concurrency, distributed message passing, and REST API interaction.

This project was developed to explore distributed systems architecture, actor-based concurrency, and backend service design.

# Project Overview

The system models a simplified Reddit platform with support for:

* Users
* Subreddits
* Posts
* Comments
* Voting
* Direct Messaging
* Feed generation

The backend components run as independent actors (processes) that communicate using message passing on the Erlang VM. A simulation layer generates large numbers of user interactions to evaluate system behavior and scalability. An HTTP API server exposes the engine functionality so that external clients can interact with the system.
