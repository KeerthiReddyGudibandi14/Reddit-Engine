<p align="center">
  <img src="https://readme-typing-svg.herokuapp.com?size=32&color=000000&center=true&vCenter=true&width=900&lines=Reddit+Engine;Actor-Based+Distributed+System">
</p>

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

## System Architecture

The Reddit Engine is built using an actor-based distributed architecture
running on the Erlang VM. Each component runs as an independent process
communicating through message passing.

```mermaid
graph TD
Client --> API Server
API Server --> Reddit_Engine
Reddit_Engine --> User Registry
Reddit_Engine --> Subreddit Registry
Reddit_Engine --> Content Coordinator
Reddit_Engine --> DM Router

Content Coordinator --> Posts
Content Coordinator --> Comments
Content Coordinator --> Voting
