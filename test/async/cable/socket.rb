# frozen_string_literal: true

require "async/cable/socket"
require "action_cable"

describe Async::Cable::Socket do
	let(:socket) {subject.new({}, nil, ::ActionCable::Server::Base.new)}
	
	it "transmit returns nil after close" do
		socket.close
		expect(socket.transmit({type: "ping"})).to be_nil
	end
	
	it "close is idempotent" do
		socket.close
		socket.close
	end
end
