# Released under the MIT License.
# Copyright, 2023-2024, by Samuel Williams.

require 'async/websocket/adapters/rack'

module Async::Cable
	class Server(app)
		def initialize(bus = Bus::Local.new, **options)
			@bus = bus
			@app = app
		end
		
		def channel_klass(identifier)
			Object.const_get(identifier[:channel])
		end
		
		def accept(connection)
			while message = connection.read
				command = data[:command]
				
				case command
				when "subscribe"
					connection.handle_subscribe(data[:identifier], @bus)
				when "unsubscribe"
					connection.handle_unsubscribe(data[:identifier], @bus)
				when "message"
					connection.handle_message(data[:identifier], data[:data], @bus)
				else
					Console.error(self, "Unknown command: #{command}", connection: connection)
				end
			end
		ensure
			@bus.disconnect(connection)
		end
		
		def call(env)
			Async::WebSocket::Adapters::Rack.open(env, Async::Cable::Connection) do |connection|
				accept(connection)
			end or @app.call(env)
		end
	end
end
