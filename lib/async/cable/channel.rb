module Async::Cable
	class Channel
		def initialize(connection, bus)
			@connection = connection
			@bus = bus
		end
		
		def stream_for(name)
			@bus.subscribe(name, self)
		end
		
		
	end
end
