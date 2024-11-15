# Released under the MIT License.
# Copyright, 2023-2024, by Samuel Williams.

require 'async/websocket/connection'

module Async::Cable
	class Connection < Async::WebSocket::Connection
		def channels
			@channels ||= Hash.new
		end
		
		def handle_subscribe(identifier, bus)
			options = JSON.parse(identifier, symbolize_names: true)
			klass = Object.const_get(options[:channel])
			channel = klass.new(self, bus, **options)
			
			channels[identifier] = channel
		end
		
		def handle_unsubscribe(identifier, bus)
			channels[identifier].unsubscribe
		end
		
		def handle_message(identifier, data, bus)
			channels[identifier].receive(data)
		end
	end
end
