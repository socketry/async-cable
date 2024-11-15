require 'async/websocket/adapters/rack'

require_relative 'socket'
require_relative 'executor'

module Async
	module Cable
		def self.default_server
			::ActionCable.server.tap do |server|
				server.instance_variable_set(:@executor, Executor.new)
			end
		end
		
		class Middleware
			def initialize(app, server: Cable.default_server)
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
				
				# Action Cable connection instance
				connection = @server.config.connection_class.call.new(@server, socket)
				
				connection.handle_open
				
				@server.setup_heartbeat_timer
				@server.add_connection(connection)
				
				while message = websocket.read
					connection.handle_incoming(@coder.decode(message.buffer))
				end
			rescue Protocol::WebSocket::ClosedError
				# This is a normal disconnection.
			rescue => error
				Console.warn(self, error)
			ensure
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
