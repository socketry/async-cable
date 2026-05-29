# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Tom and contributors.
# Copyright, 2026, by Samuel Williams.

require "async"
require "async/redis"

module ActionCable
	module SubscriptionAdapter
		# Fiber-based Redis pub/sub adapter for Action Cable, built on
		# {Async::Redis::Client}.
		#
		# Action Cable adapters are process-global and called from arbitrary
		# threads (HTTP request threads, the Action Cable executor pool,
		# background jobs, etc.). To keep all Redis I/O on a single reactor
		# without putting any constraints on callers, the adapter owns one
		# dedicated thread that hosts an event loop; cross-thread requests
		# arrive via a {Thread::Queue} and are dispatched as fibers on that
		# reactor. Redis clients are never shared across threads.
		#
		# Configuration (in `config/cable.yml`):
		#
		#   production:
		#     adapter: async_redis
		#     url: redis://localhost:6379/1
		#     reconnect_attempts: 5         # or [0, 1, 2] for backoff
		#     channel_prefix: my_app
		class AsyncRedis < Base
			prepend ChannelPrefix
			
			# Sentinel pushed into the inbox to terminate the reactor thread.
			SHUTDOWN = :shutdown
			
			# Create a new adapter instance.
			def initialize(*)
				super
				@mutex = ::Mutex.new
				@inbox = nil
				@thread = nil
			end
			
			# Publish a payload to a Redis channel. Safe to call from any
			# thread or fiber; the work is queued onto the adapter's dedicated
			# reactor thread.
			# @parameter channel [String] The Redis channel name.
			# @parameter payload [String] The encoded message payload.
			def broadcast(channel, payload)
				inbox.push([:broadcast, channel, payload])
			end
			
			# Subscribe to a Redis channel. The `success_callback` (if given)
			# is invoked once the subscription has been issued.
			# @parameter channel [String] The Redis channel name.
			# @parameter callback [Proc] Invoked with each received payload.
			# @parameter success_callback [Proc, nil] Invoked after subscribe.
			def subscribe(channel, callback, success_callback = nil)
				inbox.push([:subscribe, channel, callback, success_callback])
			end
			
			# Remove a previously-registered subscription.
			# @parameter channel [String] The Redis channel name.
			# @parameter callback [Proc] The callback originally passed to `#subscribe`.
			def unsubscribe(channel, callback)
				inbox.push([:unsubscribe, channel, callback])
			end
			
			# Shut down the adapter, closing both Redis clients and stopping
			# the reactor thread.
			def shutdown
				@mutex.synchronize do
					return unless @thread
					@inbox.push(SHUTDOWN)
					@thread.join
					@thread = nil
					@inbox = nil
				end
			end
			
			private
			
			def inbox
				@inbox || @mutex.synchronize{@inbox ||= start_reactor_thread}
			end
			
			def start_reactor_thread
				inbox = ::Thread::Queue.new
				@thread = ::Thread.new do
					::Thread.current.name = "async-cable redis adapter"
					Sync do
						Worker.new(inbox, endpoint, executor, logger: logger, reconnect_attempts: reconnect_attempts).run
					end
				end
				inbox
			end
			
			def endpoint
				@endpoint ||= if url = config_options[:url]
					::Async::Redis::Endpoint.parse(url)
				else
					::Async::Redis::Endpoint.local
				end
			end
			
			def reconnect_attempts
				value = config_options.fetch(:reconnect_attempts, 1)
				value.is_a?(Integer) ? Array.new(value, 0) : Array(value)
			end
			
			def config_options
				@config_options ||= config.cable.deep_symbolize_keys.merge(id: identifier)
			end
			
			# Lives entirely on the adapter's reactor thread. Owns one
			# {Async::Redis::Client} that is shared between publishing and
			# subscribing: PUBLISH acquires a pooled connection per call,
			# while a single long-lived {Context::Subscription} multiplexes
			# every channel the adapter has subscribed to.
			#
			# All access to the client happens on this thread's reactor, so
			# the pool's internal `Async::Semaphore` (which is not
			# thread-safe) is only ever touched from one thread.
			class Worker
				def initialize(inbox, endpoint, executor, logger: nil, reconnect_attempts: [0])
					@inbox = inbox
					@endpoint = endpoint
					@executor = executor
					@logger = logger
					@reconnect_attempts = reconnect_attempts
					
					@client = nil
					@subscribers = ::Hash.new{|hash, key| hash[key] = []}
					@subscriber_context = nil
					@pending_subscribes = []
				end
				
				# Main reactor-thread entry point.
				def run
					@client = ::Async::Redis::Client.new(@endpoint)
					task = ::Async::Task.current
					
					listener_task = task.async{run_listener}
					
					while (command = @inbox.pop)
						break if command == SHUTDOWN
						
						# Dispatch as a fiber so a slow PUBLISH (network stall)
						# can't block subsequent commands or message delivery:
						task.async{dispatch(command)}
					end
				ensure
					listener_task&.stop
					@client&.close
				end
				
				private
				
				def dispatch(command)
					case command.first
					when :broadcast
						_, channel, payload = command
						@client.call("PUBLISH", channel, payload)
					when :subscribe
						_, channel, callback, success_callback = command
						local_subscribe(channel, callback)
						@executor.post(&success_callback) if success_callback
					when :unsubscribe
						_, channel, callback = command
						local_unsubscribe(channel, callback)
					end
				rescue => error
					@logger&.error("AsyncRedis dispatch (#{command.first}): #{error.class}: #{error.message}")
				end
				
				def local_subscribe(channel, callback)
					new_channel = @subscribers[channel].empty?
					@subscribers[channel] << callback
					return unless new_channel
					
					if @subscriber_context
						@subscriber_context.subscribe([channel])
					else
						# Listener still connecting; it will pick this up on
						# connect:
						@pending_subscribes << channel
					end
				end
				
				def local_unsubscribe(channel, callback)
					return unless @subscribers.key?(channel)
					@subscribers[channel].delete(callback)
					return unless @subscribers[channel].empty?
					
					@subscribers.delete(channel)
					@subscriber_context&.unsubscribe([channel])
				end
				
				# Long-lived task that maintains the SUBSCRIBE connection and
				# routes incoming messages back to subscribers via the Action
				# Cable executor.
				def run_listener
					attempts = 0
					
					loop do
						begin
							@client.subscribe("_async_cable_internal") do |context|
								@subscriber_context = context
								
								# Resubscribe everything we already know about,
								# plus anything queued while disconnected:
								initial = @subscribers.keys | @pending_subscribes
								@pending_subscribes.clear
								context.subscribe(initial) unless initial.empty?
								
								context.each do |_type, channel, data|
									next unless data
									@subscribers[channel]&.each do |callback|
										@executor.post{callback.call(data)}
									end
								end
							end
							
							attempts = 0
						rescue => error
							@subscriber_context = nil
							raise if attempts >= @reconnect_attempts.size
							
							@logger&.error("AsyncRedis listener: #{error.class}: #{error.message}")
							delay = @reconnect_attempts[attempts]
							::Async::Task.current.sleep(delay) if delay && delay > 0
							attempts += 1
						ensure
							@subscriber_context = nil
						end
					end
				end
			end
		end
	end
end
