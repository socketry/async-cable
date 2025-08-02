# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024, by Samuel Williams.

module Async::Cable
	class Socket
		def initialize(env, websocket, server, coder: ActiveSupport::JSON)
			@env = env
			@websocket = websocket
			@server = server
			@coder = coder
			
			@output = ::Thread::Queue.new
		end
		
		attr :env
		
		def logger
			@server.logger
		end
		
		def request
			# Copied from ActionCable::Server::Socket#request
			@request ||= begin
				if defined?(Rails.application) && Rails.application
					environment = Rails.application.env_config.merge(@env)
				end
				
				ActionDispatch::Request.new(environment || @env)
			end
		end
		
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
		
		def transmit(data)
			# Console.info(self, "Transmitting data:", data, task: Async::Task.current?)
			@output.push(@coder.encode(data))
		end
		
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
