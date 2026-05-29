# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Tom and contributors.
# Copyright, 2026, by Samuel Williams.

require "action_cable"
require "active_support/core_ext/hash"
require "concurrent"
require "async/cable"
require "action_cable/subscription_adapter/async_redis"
require "sus/fixtures/async"

REDIS_URL = ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379")

# Cheap TCP-level probe so the suite cleanly skips when Redis isn't running
# (e.g. local development). CI provides a Redis service container.
REDIS_AVAILABLE = begin
	require "socket"
	uri = URI.parse(REDIS_URL)
	Socket.tcp(uri.host, uri.port, connect_timeout: 1).close
	true
rescue StandardError
	false
end

describe ActionCable::SubscriptionAdapter::AsyncRedis do
	include Sus::Fixtures::Async::ReactorContext
	
	let(:cable_server) {::ActionCable::Server::Base.new}
	
	before do
		cable_server.config.logger = Console
		cable_server.config.cable = {
			"adapter" => "async_redis",
			"url" => REDIS_URL,
		}
	end
	
	let(:adapter) {subject.new(cable_server)}
	
	it "is resolvable via Action Cable configuration" do
		expect(cable_server.config.pubsub_adapter).to be == subject
	end
	
	with "a running Redis", if: REDIS_AVAILABLE do
		after do
			adapter.shutdown
		end
		
		it "round-trips a message from broadcast to subscriber" do
			received = ::Thread::Queue.new
			subscribed = ::Thread::Queue.new
			
			adapter.subscribe("test-channel", ->(message){received.push(message)}, ->{subscribed.push(true)})
			
			# Wait for the subscription to be issued before broadcasting,
			# otherwise the message can be published into the void:
			subscribed.pop
			
			adapter.broadcast("test-channel", "hello world")
			
			expect(received.pop).to be == "hello world"
		end
		
		it "delivers to multiple subscribers on the same channel" do
			received_a = ::Thread::Queue.new
			received_b = ::Thread::Queue.new
			ready = ::Thread::Queue.new
			
			adapter.subscribe("multi-channel", ->(m){received_a.push(m)}, ->{ready.push(true)})
			adapter.subscribe("multi-channel", ->(m){received_b.push(m)}, ->{ready.push(true)})
			
			2.times{ready.pop}
			
			adapter.broadcast("multi-channel", "fanout")
			
			expect(received_a.pop).to be == "fanout"
			expect(received_b.pop).to be == "fanout"
		end
		
		it "stops delivering after unsubscribe" do
			received = ::Thread::Queue.new
			subscribed = ::Thread::Queue.new
			callback = ->(message){received.push(message)}
			
			adapter.subscribe("toggle-channel", callback, ->{subscribed.push(true)})
			subscribed.pop
			
			adapter.unsubscribe("toggle-channel", callback)
			
			# Round-trip a sentinel message via a second subscriber to confirm
			# the UNSUBSCRIBE has been processed by the server:
			sentinel = ::Thread::Queue.new
			adapter.subscribe("toggle-channel-sentinel", ->(m){sentinel.push(m)}, ->{sentinel.push(:ready)})
			sentinel.pop # :ready
			
			adapter.broadcast("toggle-channel", "should not arrive")
			adapter.broadcast("toggle-channel-sentinel", "sync")
			
			expect(sentinel.pop).to be == "sync"
			expect(received).to be(:empty?)
		end
	end
end
