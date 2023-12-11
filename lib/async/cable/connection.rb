require 'async/websocket/connection'

module Async::Cable
	class Connection < Async::WebSocket::Connection
		def channels
			@channels ||= Hash.new
		end
		
		def handle_subscribe(identifier, bus)
			klass = Object.const_get(identifier[:channel])
			channel = klass.new(self, bus)
			
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
