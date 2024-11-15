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
			@connection.write(@coder.encode(data))
			@connection.flush
		rescue IOError, Errno::EPIPE => error
			logger.debug "Failed to write to the socket: #{error.message}"
		end
		
		def close
			@connection.close
		end
		
		def perform_work(receiver, ...)
			Async do
				receiver.send(...)
			rescue Exception => error
				logger.error "There was an exception - #{error.class}(#{error.message})"
				logger.error error.backtrace.join("\n")
				
				receiver.handle_exception if receiver.respond_to?(:handle_exception)
			end
		end
	end
end
