# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024-2026, by Samuel Williams.

module Async
	module Cable
		# Wraps a WebSocket connection to provide the interface expected by ActionCable connections. Buffers outbound messages in a queue and drains them asynchronously so that transmission never blocks the event loop.
		class Socket
			# Create a new socket wrapper.
			# @parameter env [Hash] The Rack environment for the originating request.
			# @parameter websocket [Async::WebSocket::Connection] The underlying WebSocket connection.
			# @parameter server [ActionCable::Server::Base] The ActionCable server instance.
			# @parameter coder [#encode, #decode] Coder used to serialise messages (defaults to `ActiveSupport::JSON`).
			def initialize(env, websocket, server, coder: ActiveSupport::JSON)
				@env = env
				@websocket = websocket
				@server = server
				@coder = coder
				
				@output = ::Thread::Queue.new
			end
			
			attr :env
			
			# The ActionCable server logger.
			# @returns [Logger]
			def logger
				@server.logger
			end
			
			# Build an `ActionDispatch::Request` from the Rack environment, merging Rails application config when available.
			# @returns [ActionDispatch::Request]
			def request
				# Copied from `ActionCable::Server::Socket#request`:
				@request ||= begin
					if defined?(Rails.application) && Rails.application
						environment = Rails.application.env_config.merge(@env)
					end
					
					ActionDispatch::Request.new(environment || @env)
				end
			end
			
			# Start an async task that drains the outbound message queue and writes each message to the WebSocket. The task stops when the queue is closed.
			# @parameter parent [Async::Task] The parent task to spawn under.
			# @returns [Async::Task]
			def run(parent: Async::Task.current)
				parent.async do
					while buffer = @output.pop
						# Console.debug(self, "Sending cable data:", buffer, flush: @output.empty?)
						@websocket.send_text(buffer)
						@websocket.flush if @output.empty?
					end
				rescue => error
					Console.error(self, "Error while sending cable data:", error)
				ensure
					unless @websocket.closed?
						@websocket.close_write(error)
					end
				end
			end
			
			# Encode and enqueue a message for asynchronous delivery to the client.
			# @parameter data [Object] The data to transmit, which will be encoded by the coder.
			def transmit(data)
				# Console.info(self, "Transmitting data:", data, task: Async::Task.current?)
				@output.push(@coder.encode(data))
			end
			
			# Close the outbound queue, causing the drain task to terminate once all pending messages have been sent.
			def close
				# Console.info(self, "Closing socket.", task: Async::Task.current?)
				@output.close
			end
			
			# This can be called from the work pool, off the event loop.
			def perform_work(receiver, ...)
				# Console.info(self, "Performing work:", receiver)
				receiver.send(...)
			end
		end
	end
end
