#!/usr/bin/env ruby
# frozen_string_literal: true

url = ARGV.pop || "http://localhost:8080/cable"

require "async"
require "async/http/endpoint"
require "async/websocket"

OPTIONS = {
	# Disable compression:
	extensions: nil
}

IDENTIFIER = {channel: "BenchmarkChannel"}.to_json

SUBSCRIBE_MESSAGE = Protocol::WebSocket::TextMessage.generate(
	command: "subscribe",
	identifier: IDENTIFIER
)

CONNECTION_COUNT = ENV.fetch("CONNECTIONS", 1000).to_i
BROADCAST_COUNT = ENV.fetch("BROADCASTS", 20).to_i

def connect(endpoint, count: 100, parent: Async::Task.current)
	count.times.map do
		parent.async do
			connection = Async::WebSocket::Client.connect(endpoint, **OPTIONS)
			
			SUBSCRIBE_MESSAGE.send(connection)
			connection.flush
			
			while message = connection.read
				parsed = message.parse
				break if parsed[:type] == "confirm_subscription"
			end
			
			connection
		end
	end.map(&:wait)
end

def broadcast(connections, data, count: 10, parent: Async::Task.current)
	broadcast_message = Protocol::WebSocket::TextMessage.generate(
		command: "message",
		identifier: IDENTIFIER,
		data: data.to_json
	)
	
	broadcast_connection = connections.first
	
	parent.async do
		count.times do
			broadcast_message.send(broadcast_connection)
			broadcast_connection.flush
		end
	end
	
	connections.map do |connection|
		parent.async do
			count.times do |i|
				while message = connection.read
					parsed = message.parse
					if parsed[:identifier] == IDENTIFIER
						break
					end
				end
			end
		end
	end.map(&:wait)
end

def format_duration(duration)
	if duration > 1
		"%.3fs" % duration
	else
		"%.3fms" % (duration * 1000)
	end
end

Async do
	endpoint = Async::HTTP::Endpoint.parse(url)
	connections = nil
	
	duration = Async::Clock.measure do
		connections = connect(endpoint, count: CONNECTION_COUNT)
	end
	
	puts "Connected #{connections.size} clients in #{format_duration(duration)}."
	puts "Amortized connection time: #{format_duration(duration / CONNECTION_COUNT)}."
	puts "Amortized connection rate: #{(CONNECTION_COUNT / duration).round(2)} clients/s."
	
	duration = Async::Clock.measure do
		broadcast(connections, {action: "broadcast", payload: "Hello, World!"}, count: BROADCAST_COUNT)
	end
	
	puts "Broadcast #{BROADCAST_COUNT} times to #{connections.size} clients in #{format_duration(duration)}."
	puts "Amortized broadcast time: #{format_duration(duration / (CONNECTION_COUNT * BROADCAST_COUNT))}."
	puts "Amortized broadcast rate: #{(CONNECTION_COUNT * BROADCAST_COUNT / duration).round(2)} broadcasts/s."
	
	connections&.each do |connection|
		connection.shutdown
	end
ensure
	connections&.each do |connection|
		connection.close
	end
end
