# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024-2026, by Samuel Williams.

require "async/cable/middleware"

require "protocol/rack/adapter"
require "async/websocket/client"
require "sus/fixtures/async/http/server_context"

require "test_channel"

describe Async::Cable::Middleware do
	include Sus::Fixtures::Async::HTTP::ServerContext
	
	def url
		"http://localhost:0/cable"
	end
	
	let(:cable_server) {::ActionCable::Server::Base.new}
	
	before do
		cable_server.config.disable_request_forgery_protection = true
		cable_server.config.logger = Console
		cable_server.config.cable = {"adapter" => "async"}
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
	
	with "non-websocket requests" do
		let(:inner_app) do
			lambda do |env|
				[200, {"content-type" => "text/plain"}, ["hello"]]
			end
		end
		
		let(:app) do
			Protocol::Rack::Adapter.new(subject.new(inner_app, server: cable_server))
		end
		
		it "forwards non-websocket requests on the cable path to the inner app" do
			response = client.get("/cable")
			expect(response.read).to be == "hello"
		ensure
			response&.close
		end
		
		it "forwards requests on other paths to the inner app" do
			response = client.get("/other")
			expect(response.read).to be == "hello"
		ensure
			response&.close
		end
	end
	
	with "#allow_request_origin?" do
		let(:middleware) {subject.new(nil, server: cable_server)}
		
		before do
			cable_server.config.disable_request_forgery_protection = false
		end
		
		it "allows requests matching the configured origin host" do
			cable_server.config.allow_same_origin_as_host = true
			env = {"HTTP_ORIGIN" => "http://example.com", "HTTP_HOST" => "example.com", "rack.url_scheme" => "http"}
			expect(middleware.__send__(:allow_request_origin?, env)).to be == true
		end
		
		it "allows requests from explicitly allowed origins" do
			cable_server.config.allowed_request_origins = ["http://allowed.example"]
			env = {"HTTP_ORIGIN" => "http://allowed.example", "HTTP_HOST" => "example.com", "rack.url_scheme" => "http"}
			expect(middleware.__send__(:allow_request_origin?, env)).to be == true
		end
		
		it "rejects requests from disallowed origins" do
			cable_server.config.allowed_request_origins = ["http://allowed.example"]
			env = {"HTTP_ORIGIN" => "http://evil.example", "HTTP_HOST" => "example.com", "rack.url_scheme" => "http"}
			expect(middleware.__send__(:allow_request_origin?, env)).to be == false
		end
	end
	
	with "#handle_incoming_websocket" do
		include Sus::Fixtures::Async::ReactorContext
		
		let(:middleware) {subject.new(nil, server: cable_server)}
		
		# Minimal websocket double whose `read` raises an unexpected error,
		# exercising the abnormal-failure rescue branch.
		let(:failing_websocket) do
			Class.new do
				def read; raise "unexpected"; end
				def send_text(_); end
				def flush; end
				def closed?; true; end
				def close_write(_ = nil); end
			end.new
		end
		
		it "logs unexpected errors and cleans up the connection" do
			env = {"PATH_INFO" => "/cable", "HTTP_HOST" => "example.com", "rack.url_scheme" => "http"}
			middleware.__send__(:handle_incoming_websocket, env, failing_websocket)
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
	
	it "handles server restart cleanly when a channel transmits during unsubscribed" do
		# Subscribe to the channel so TestChannel#unsubscribed will be triggered on close.
		subscribe_message = ::Protocol::WebSocket::TextMessage.generate({
			command: "subscribe",
			identifier: identifier,
		})
		
		subscribe_message.send(connection)
		
		while message = connection.read
			break if message.parse[:type] == "confirm_subscription"
		end
		
		# Restart closes every connection: connection.close sends the disconnect
		# frame then calls socket.close, which closes the output queue. The
		# middleware ensure block then calls connection.handle_close, which runs
		# TestChannel#unsubscribed, which calls transmit on the now-closed socket.
		cable_server.restart
		
		while message = connection.read
			break if message.parse[:type] == "disconnect"
		end
	ensure
		connection.close
	end
	
	it "restart does not raise when called while a prior restart is still being cleaned up" do
		# Establish a subscribed connection so there is an entry in the server's
		# connections list.
		subscribe_message = ::Protocol::WebSocket::TextMessage.generate({
			command: "subscribe",
			identifier: identifier,
		})
		
		subscribe_message.send(connection)
		
		while message = connection.read
			break if message.parse[:type] == "confirm_subscription"
		end
		
		# First restart: calls connection.close on every connection, which sends
		# the disconnect frame and closes the socket's output queue.  The
		# connection is NOT removed from the list here — that only happens in the
		# middleware's ensure block, which runs asynchronously after the WebSocket
		# loop exits.
		cable_server.restart
		
		# Second restart immediately (no yield to the scheduler) — the connection
		# is still in the list but its socket is already closed, so
		# connection.close → transmit(disconnect) → queue.push raises
		# ClosedQueueError.
		cable_server.restart
	ensure
		connection.close
	end
end
