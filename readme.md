# Async::Cable

This is a proof-of-concept adapter for Action Cable.

The `next` branch tracks Rails `main` and relies on the `ActionCable::Server::Socket` abstraction introduced by [rails/rails#50979](https://github.com/rails/rails/pull/50979) (Rails 8.1+). For stable Rails (≤ 8.0), use the `main` branch, which depends on [`actioncable-next`](https://github.com/anycable/actioncable-next).

[![Development Status](https://github.com/socketry/async-cable/workflows/Test/badge.svg)](https://github.com/socketry/async-cable/actions?workflow=Test)

## Usage

Please see the [project documentation](https://socketry.github.io/async-cable/) for more details.

  - [Getting Started](https://socketry.github.io/async-cable/guides/getting-started/index) - This guide shows you how to add `async-cable` to your project to enable real-time communication between clients and servers using Falcon and Action Cable.

### Async Redis Adapter

`async-cable` ships with a fiber-based Redis subscription adapter: `async_redis`. It mirrors Rails' built-in `redis` adapter (dynamic subscribe/unsubscribe, reconnect + resubscribe) but uses [`async-redis`](https://github.com/socketry/async-redis) so all I/O runs cooperatively on the fiber scheduler instead of blocking a thread.

Configure Action Cable to use it by setting `adapter: async_redis` in `config/cable.yml`:

```yaml
production:
  adapter: async_redis
  url: <%= ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0") %>
  # Optional:
  channel_prefix: <%= "#{Rails.application.class.module_parent_name.underscore}_production" %>
  reconnect_attempts: [0, 1, 2, 5]
```

`reconnect_attempts` accepts either an integer (retry that many times with no delay) or an array of per-attempt delays in seconds.

Notes:

- Broadcasting (`#broadcast`) is safe to call from any thread or fiber. When the caller is already inside a reactor it runs cooperatively; otherwise a transient reactor is opened via `Sync { }`.
- The subscription listener runs on a single dedicated thread hosting its own reactor and shared across all channels.
- `success_callback` is invoked immediately after issuing `SUBSCRIBE` (async-redis does not expose subscribe ACKs).

## Releases

Please see the [project releases](https://socketry.github.io/async-cable/releases/index) for all releases.

### v0.3.0

  - Filter requests based on path - don't eat all inbound WebSocket connections.

### v0.2.0

  - Don't close the WebSocket if it is already closed.

### v0.1.0

  - Initial implementation.

## Contributing

We welcome contributions to this project.

1.  Fork it.
2.  Create your feature branch (`git checkout -b my-new-feature`).
3.  Commit your changes (`git commit -am 'Add some feature'`).
4.  Push to the branch (`git push origin my-new-feature`).
5.  Create new Pull Request.

### Running Tests

To run the test suite:

``` shell
bundle exec sus
```

### Making Releases

To make a new release:

``` shell
bundle exec bake gem:release:patch # or minor or major
```

### Developer Certificate of Origin

In order to protect users of this project, we require all contributors to comply with the [Developer Certificate of Origin](https://developercertificate.org/). This ensures that all contributions are properly licensed and attributed.

### Community Guidelines

This project is best served by a collaborative and respectful environment. Treat each other professionally, respect differing viewpoints, and engage constructively. Harassment, discrimination, or harmful behavior is not tolerated. Communicate clearly, listen actively, and support one another. If any issues arise, please inform the project maintainers.
