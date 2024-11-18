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
	end
	
	after do
		@cable_server&.restart
	end
	
	let(:app) do
		Protocol::Rack::Adapter.new(subject.new(nil, server: cable_server))
	end
	
	let(:connection) {Async::WebSocket::Client.connect(client_endpoint)}
	
	it "can connect and receive welcome messages" do
		welcome_message = connection.read.parse
		
		expect(welcome_message).to have_keys(
			type: be == "welcome"
		)
	ensure
		connection.close
	end
	
	it "can connect and send broadcast messages" do
		subscribe_message = ::Protocol::WebSocket::TextMessage.generate({
			command: "subscribe",
			identifier: JSON.dump({"channel" => "TestChannel"}),
		})
		
		subscribe_message.send(connection)
		
		while message = connection.read
			confirmation = message.parse
			
			if confirmation[:type] == "confirm_subscription"
				break
			end
		end
		
		expect(confirmation).to have_keys(
			identifier: be == JSON.dump({"channel" => "TestChannel"})
		)
	ensure
		connection.close
	end
end
