# Released under the MIT License.
# Copyright, 2024, by Samuel Williams.

require 'async/websocket/adapters/rack'

require_relative 'socket'

module Async
	module Cable
		class Middleware
			def initialize(app, server: ActionCable.server)
				@app = app
				@server = server
				@coder = ActiveSupport::JSON
				@protocols = ::ActionCable::INTERNAL[:protocols]
			end
			
			def call(env)
				if Async::WebSocket::Adapters::Rack.websocket?(env) and allow_request_origin?(env)
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
				
				@server.setup_heartbeat_timer
				@server.add_connection(connection)
				
				output_task = Async do
					while message = socket.output.pop
						Console.debug(self, "Sending cable data:", message)
						websocket.write(message)
						websocket.flush if socket.output.empty?
					end
				end
				
				while message = websocket.read
					Console.debug(self, "Received cable data:", message)
					connection.handle_incoming(@coder.decode(message.buffer))
				end
			rescue Protocol::WebSocket::ClosedError
				# This is a normal disconnection.
			rescue => error
				Console.warn(self, error)
			ensure
				if output_task
					output_task.stop
				end
				
				if connection
					@server.remove_connection(connection)
					connection.handle_close
				end
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
