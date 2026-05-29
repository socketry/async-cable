# Releases

## Unreleased

  - Add {ruby Async::Cable::Socket#raw_transmit} for pushing pre-encoded payloads to the client without re-encoding. Enables "fastlane" broadcasts that encode the message once and share it across many connections.

## v0.3.0

  - Filter requests based on path - don't eat all inbound WebSocket connections.

## v0.2.0

  - Don't close the WebSocket if it is already closed.

## v0.1.0

  - Initial implementation.
