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
			
			@write_guard = Mutex.new
		end
		
		attr :env
		attr :output
		
		def logger
			Console
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
		
		def transmit(data)
			@write_guard.synchronize do
				@websocket.write(@coder.encode(data))
				@websocket.flush
			end
		end
		
		def close
			@write_guard.synchronize do
				@websocket.close
			end
		end
		
		def perform_work(receiver, ...)
			Async::Task.current.async do
				receiver.send(...)
			end
		end
	end
end
