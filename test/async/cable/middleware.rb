# frozen_string_literal: true
require "async/cable/middleware"

require "protocol/rack/adapter"
require "async/websocket/client"
require "sus/fixtures/async/http/server_context"

require "test_channel"

describe Async::Cable::Middleware do
	include Sus::Fixtures::Async::HTTP::ServerContext
	
	let(:cable_server) {::ActionCable::Server::Base.new}
	
	before do
		cable_server.config.disable_request_forgery_protection = true
		cable_server.config.logger = Console
		cable_server.config.cable = {"adapter" => "async"}
	end
	
	after do
		@cable_server&.restart
	end
	
	let(:app) do
		Protocol::Rack::Adapter.new(subject.new(nil, server: cable_server))
	end
	
	let(:connection) {Async::WebSocket::Client.connect(client_endpoint)}
	
	let(:identifier) {JSON.dump(channel: "TestChannel")}
	
	it "can connect and receive welcome messages" do
		welcome_message = connection.read.parse
		
		expect(welcome_message).to have_keys(
			type: be == "welcome"
		)
		
		connection.shutdown
	ensure
		connection.close
	end
	
	it "can connect and send broadcast messages" do
		subscribe_message = ::Protocol::WebSocket::TextMessage.generate({
			command: "subscribe",
			identifier: identifier,
		})
		
		subscribe_message.send(connection)
		
		while message = connection.read
			confirmation = message.parse
			
			if confirmation[:type] == "confirm_subscription"
				break
			end
		end
		
		expect(confirmation).to have_keys(
			identifier: be == identifier
		)
		
		broadcast_data = {action: "broadcast", payload: "Hello, World!"}
		
		broadcast_message = Protocol::WebSocket::TextMessage.generate(
			command: "message",
			identifier: identifier,
			data: broadcast_data.to_json
		)
		
		broadcast_message.send(connection)
		connection.flush
		
		while message = connection.read
			broadcast = message.parse
			
			if broadcast[:identifier] == identifier
				break
			end
		end
		
		expect(broadcast).to have_keys(
			identifier: be == identifier
		)
		
		connection.shutdown
	ensure
		connection.close
	end
end
