# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/websocket/adapters/rack"
require "action_cable"

require_relative "executor"
require_relative "socket"

module Async
	module Cable
		# Action Cable server implementation backed by Async WebSocket handling.
		class Server < ::ActionCable::Server::Base
			# Initialize the server with the given Action Cable configuration.
			# @parameter config [ActionCable::Configuration] The Action Cable configuration.
			def initialize(config)
				super(config)
				
				@coder = ActiveSupport::JSON
				@protocols = ::ActionCable::INTERNAL[:protocols]
			end
			
			# Executor used by pub/sub callbacks, heartbeat timers, and periodic channel timers.
			def executor
				@executor || @mutex.synchronize{@executor ||= Executor.new}
			end
			
			# Called by Rack to handle the mounted Action Cable endpoint.
			def call(env)
				return config.health_check_application.call(env) if env["PATH_INFO"] == config.health_check_path
				
				if Async::WebSocket::Adapters::Rack.websocket?(env) and allow_request_origin?(env)
					Async::WebSocket::Adapters::Rack.open(env, protocols: @protocols) do |websocket|
						handle_incoming_websocket(env, websocket)
					end
				else
					[404, {Rack::CONTENT_TYPE => "text/plain; charset=utf-8"}, ["Page not found"]]
				end
			end
			
			private
			
			def handle_incoming_websocket(env, websocket)
				socket = Socket.new(env, websocket, self, coder: @coder)
				connection = config.connection_class.call.new(self, socket)
				
				connection.handle_open
				add_connection(connection)
				setup_heartbeat_timer
				
				socket_task = socket.run
				
				while message = websocket.read
					# Console.debug(self, "Received cable data:", message.buffer)
					connection.handle_incoming(@coder.decode(message.buffer))
				end
			rescue Protocol::WebSocket::ClosedError, EOFError
				# This is a normal disconnection.
			rescue => error
				Console.warn(self, "Abnormal client failure!", error)
			ensure
				if connection
					remove_connection(connection)
					connection.handle_close
				end
				
				socket_task&.stop
			end
		end
	end
end
