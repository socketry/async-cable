# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024-2026, by Samuel Williams.

require "async/websocket/adapters/rack"
require "action_cable"

require_relative "socket"

module Async
	module Cable
		# Rack middleware that intercepts WebSocket upgrade requests and dispatches them to ActionCable, passing all other requests to the next app in the middleware stack.
		class Middleware
			# Create a new middleware instance.
			# @parameter app [#call] The next Rack application in the middleware stack.
			# @parameter path [String] The URL path that the cable endpoint is mounted at.
			# @parameter server [ActionCable::Server::Base] The ActionCable server to use.
			def initialize(app, path: "/cable", server: ActionCable.server)
				@app = app
				@path = path
				@server = server
				@coder = ActiveSupport::JSON
				@protocols = ::ActionCable::INTERNAL[:protocols]
			end
			
			attr :server
			
			# Check whether the request path matches the configured cable path.
			# @parameter env [Hash] The Rack environment.
			# @returns [Boolean] Whether the request is for the cable endpoint.
			def valid_path?(env)
				env["PATH_INFO"] == @path
			end
			
			# Handle an incoming Rack request. WebSocket upgrade requests on the configured path are handed off to ActionCable; all other requests are forwarded to the next app in the middleware stack.
			# @parameter env [Hash] The Rack environment.
			# @returns [Array] A Rack response triple.
			def call(env)
				if valid_path?(env) and Async::WebSocket::Adapters::Rack.websocket?(env) and allow_request_origin?(env)
					Async::WebSocket::Adapters::Rack.open(env, protocols: @protocols) do |websocket|
						handle_incoming_websocket(env, websocket)
					end
				else
					@app.call(env)
				end
			end
			
			private
			
			def handle_incoming_websocket(env, websocket)
				socket = Socket.new(env, websocket, @server, coder: @coder)
				connection = @server.config.connection_class.call.new(@server, socket)
				
				connection.handle_open
				@server.add_connection(connection)
				@server.setup_heartbeat_timer
				
				socket_task = socket.run
				
				while message = websocket.read
					# Console.debug(self, "Received cable data:", message.buffer)
					begin
						connection.handle_incoming(@coder.decode(message.buffer))
					rescue ActionCable::Connection::Subscriptions::Error => error
						# Subscription-level errors (e.g. `AlreadySubscribedError` raised when a client re-sends a `subscribe` command, which happens during Turbo morph/refresh cycles) should not tear down the entire WebSocket connection. Log and continue so the connection (and any underlying pubsub subscriptions, like PostgreSQL `LISTEN`) stays alive.
						Console.warn(self, "Subscription error (ignored):", error)
					end
				end
			rescue Protocol::WebSocket::ClosedError, EOFError
				# This is a normal disconnection.
			rescue => error
				Console.warn(self, "Abnormal client failure!", error)
			ensure
				if connection
					@server.remove_connection(connection)
					connection.handle_close
				end
				
				socket_task&.stop
			end
			
			# TODO: Shouldn't this be moved to ActionCable::Server::Base?
			def allow_request_origin?(env)
				if @server.config.disable_request_forgery_protection
					return true
				end
				
				proto = ::Rack::Request.new(env).ssl? ? "https" : "http"
				
				if @server.config.allow_same_origin_as_host && env["HTTP_ORIGIN"] == "#{proto}://#{env["HTTP_HOST"]}"
					return true
				elsif Array(@server.config.allowed_request_origins).any?{|allowed_origin| allowed_origin === env["HTTP_ORIGIN"]}
					return true
				end
				
				Console.warn(self, "Request origin not allowed!", origin: env["HTTP_ORIGIN"])
				return false
			end
		end
	end
end
