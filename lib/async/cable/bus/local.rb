# Released under the MIT License.
# Copyright, 2023-2024, by Samuel Williams.

require 'set'

module Async::Cable
	module Bus
		class Local
			def initialize
				@subscribers = Hash.new{|hash, key| hash[key] = Set.new}
			end
			
			def subscribe(identifier, connection)
				@subscribers[identifier] << connection
			end
			
			def unsubscribe(identifier, connection)
				@connections[identifier].delete(connection)
			end
			
			# def disconnect(connection)
			# 	@subscribers.each do |identifier, connections|
			# 		connections.delete(connection)
			# 	end
			# end
			
			def broadcast(identifier, message)
				@subscribers[identifier].each do |connection|
					connection.enqueue(message)
				end
			end
		end
	end
end
