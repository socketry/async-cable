# frozen_string_literal: true

require "async/cable/socket"
require "action_cable"

describe Async::Cable::Socket do
	let(:socket) {subject.new({}, nil, ::ActionCable::Server::Base.new)}
	
	it "cannot transmit after close" do
		socket.close
		
		expect do
			socket.transmit({type: "ping"})
		end.to raise_exception(ClosedQueueError)
	end
	
	it "close is idempotent" do
		socket.close
		socket.close
	end
end
