# frozen_string_literal: true
# Released under the MIT License.
# Copyright, 2024, by Samuel Williams.

require "action_cable/subscription_adapter/base"
require "action_cable/subscription_adapter/channel_prefix"
require "action_cable/subscription_adapter/subscriber_map"

require "async/redis"

module ActionCable::SubscriptionAdapter
	class AsyncCableRedis < Base
		prepend ChannelPrefix
		
		def initialize(*arguments, endpoint: nil, **options)
			super(*arguments, **options)
			
			@endpoint = endpoint || ::Async::Redis.local_endpoint
			@client = ::Async::Redis::Client.new(endpoint)
			
			@subscriber = Subscriber.new(@client, self.executor)
		end
		
		def subscribe(channel, callback, success_callback = nil)
			@subscriber.add_subscriber(channel, callback, success_callback)
		end
		
		def unsubscribe(channel, callback)
			@subscriber.remove_subscriber(channel, callback)
		end
		
		def broadcast(channel, payload)
			@client.publish(channel, payload)
		end
		
		def shutdown
			@subscriber&.close
		end
		
		private
		
		class Subscriber < SubscriberMap::Async
			CHANNEL = "_action_cable_internal"
			
			def initialize(client, executor, parent: Async::Task.current)
				super(executor)
				
				@context = @client.subscribe(CHANNEL)
				@task = parent.async{self.listen(CHANNEL)}
			end

			def add_channel(channel, on_success)
				@context.subscribe(channel)
				on_success&.call
			end

			def remove_channel(channel)
				@context.unsubscribe(channel)
			end

			def close
				if task = @task
					@task = nil
					task.stop
				end
				
				if context = @context
					@context = nil
					context.close
				end
			end

			private

			def listen
				context.each do |type, channel, message|
					self.broadcast(event[1], event[2])
				end
			end
		end
	end
end
