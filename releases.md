# Releases

## Unreleased

  - Add {ruby Async::Cable::Socket#raw_transmit} for pushing pre-encoded payloads to the client without re-encoding. Enables "fastlane" broadcasts that encode the message once and share it across many connections.
  - Add {ruby Async::Cable::Executor}, a fiber-based replacement for `ActionCable::Server::ThreadedExecutor`. Tasks posted from inside a reactor run on the caller's reactor (no thread hop); tasks posted from outside, and all recurring timers, run on a dedicated reactor thread owned by the executor.
  - Add {ruby Async::Cable::Server} and configure it as the Action Cable server implementation when Rails exposes `config.action_cable.server`.

## v0.3.0

  - Filter requests based on path - don't eat all inbound WebSocket connections.

## v0.2.0

  - Don't close the WebSocket if it is already closed.

## v0.1.0

  - Initial implementation.
