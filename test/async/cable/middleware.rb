# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024, by Samuel Williams.

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
	
	with "#valid_path?" do
		let(:middleware) {subject.new(nil, path: "/cable")}
		
		it "returns true when PATH_INFO matches configured path" do
			env = {"PATH_INFO" => "/cable"}
			expect(middleware.valid_path?(env)).to be == true
		end
		
		it "returns false when PATH_INFO does not match configured path" do
			env = {"PATH_INFO" => "/different"}
			expect(middleware.valid_path?(env)).to be == false
		end
		
		it "returns false when PATH_INFO is nil" do
			env = {"PATH_INFO" => nil}
			expect(middleware.valid_path?(env)).to be == false
		end
		
		it "returns false when PATH_INFO is missing from env" do
			env = {}
			expect(middleware.valid_path?(env)).to be == false
		end
		
		with "custom path configuration" do
			let(:middleware) {subject.new(nil, path: "/websocket")}
			
			it "returns true when PATH_INFO matches custom path" do
				env = {"PATH_INFO" => "/websocket"}
				expect(middleware.valid_path?(env)).to be == true
			end
			
			it "returns false when PATH_INFO matches default path but not custom path" do
				env = {"PATH_INFO" => "/cable"}
				expect(middleware.valid_path?(env)).to be == false
			end
		end
	end
	
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
