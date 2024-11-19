#!/usr/bin/env ruby
# frozen_string_literal: true

require "async"
require "async/http/endpoint"
require "async/websocket/adapters/rack"

require "falcon"

require "protocol/http/middleware"
require_relative "../../lib/async/cable/middleware"

require_relative "../application"

class BenchmarkServer
	def self.run!
		Sync do
			websocket_endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:8080/cable")
			
			app = ::Falcon::Server.middleware(
				::Async::Cable::Middleware.new(
					::Protocol::HTTP::Middleware::HelloWorld
				)
			)
			
			server = Falcon::Server.new(app, websocket_endpoint)
			server.run.wait
		end
	end
end

BenchmarkServer.run!
