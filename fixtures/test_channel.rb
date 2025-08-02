# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024, by Samuel Williams.

require "action_cable"

class TestChannel < ActionCable::Channel::Base
	def subscribed
		stream_from "testing-#{test_id}"
	end
	
	def echo(data)
		transmit(data)
	end
	
	def broadcast(data)
		self.server.broadcast("testing-#{test_id}", data)
	end
	
	private def server
		@connection.send(:server)
	end
	
	private def test_id
		params[:id] || "default"
	end
end
