# Released under the MIT License.
# Copyright, 2023-2024, by Samuel Williams.

module Async::Cable
	class Channel
		def initialize(connection, bus)
			@connection = connection
			@bus = bus
		end
		
		def stream_for(name)
			@bus.subscribe(name, self)
		end
		
		def stream_from(name)
	end
end
