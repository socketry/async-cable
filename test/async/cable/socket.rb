# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024-2026, by Samuel Williams.

require "async/cable/socket"
require "action_cable"
require "action_dispatch"
require "action_dispatch/http/request"
require "sus/fixtures/async"

describe Async::Cable::Socket do
	let(:server) {::ActionCable::Server::Base.new}
	let(:socket) {subject.new({}, nil, server)}
	
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
	
	with "#request" do
		it "builds an ActionDispatch::Request from the Rack environment" do
			request = socket.request
			expect(request).to be_a(ActionDispatch::Request)
		end
		
		it "memoizes the request" do
			expect(socket.request).to be_equal(socket.request)
		end
		
		it "merges Rails.application env_config when available" do
			fake_application = Object.new
			def fake_application.env_config; {"rails.test" => true}; end
			
			rails_was_defined = defined?(Rails)
			Object.const_set(:Rails, Module.new) unless rails_was_defined
			previous = Rails.respond_to?(:application) ? Rails.application : nil
			Rails.define_singleton_method(:application){fake_application}
			
			request = socket.request
			expect(request.env["rails.test"]).to be == true
		ensure
			if rails_was_defined
				Rails.define_singleton_method(:application){previous}
			else
				Object.send(:remove_const, :Rails)
			end
		end
	end
	
	with "#run" do
		include Sus::Fixtures::Async::ReactorContext
		
		# Minimal websocket double that raises on send_text, exercising the rescue
		# branch in Socket#run.
		let(:failing_websocket) do
			Class.new do
				def send_text(_buffer); raise "boom"; end
				def flush; end
				def closed?; true; end
			end.new
		end
		
		let(:socket) {subject.new({}, failing_websocket, server)}
		
		it "logs errors raised while draining the output queue" do
			task = socket.run
			socket.transmit({type: "ping"})
			socket.close
			task.wait
		end
	end
end
