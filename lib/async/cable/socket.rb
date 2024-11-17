# Released under the MIT License.
# Copyright, 2024, by Samuel Williams.

module Async::Cable
	class Socket
		#== Action Cable socket interface ==
		attr_reader :env, :logger, :protocol
		
		delegate :worker_pool, :logger, to: :@server
		
		def initialize(env, connection, server, coder: ActiveSupport::JSON)
			@env = env
			@coder = coder
			@server = server
			@connection = connection
			@output = Thread::Queue.new
		end
		
		attr :output
		
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
			@output.push(@coder.encode(data))
		end
		
		def close
			@connection.close
		end
		
		def perform_work(receiver, ...)
			Async do
				receiver.send(...)
			end
		end
	end
end
