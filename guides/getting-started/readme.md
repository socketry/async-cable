# Getting Started

This guide shows you how to add `async-cable` to your project to enable real-time communication between clients and servers using Falcon and Action Cable.

## Installation

Add the gem to your project:

~~~ bash
$ bundle add async-cable
~~~

## Usage

To use `async-cable`, you need to add the following to your `config/application.rb`:

~~~ ruby
require "async/cable"
~~~

This will automatically configure {ruby Async::Cable::Server} as the Action Cable server implementation. Rails will mount it at the configured Action Cable mount path, where it handles incoming WebSocket connections using Async.
