#!/usr/bin/env ruby

require "bundler/inline"

# This is a demo of leveraging proposed Action Cable architecture to implement
# an SSE transport for Action Cable (without changing the user-space code, e.g., Connection and Channel classes).
#
# Start the server by running the following command:
#
#     ruby main.rb
#
# Now, you can connect to Action Cable over SSE via cURL as follows:
#
#     curl -N "http://localhost:3000/cable/events?user_id=123&identifier=%7B%22channel%22%3A%22ChatChannel%22%2C%22id%22%3A42%7D"
#
# You can also connect to the same server via WebSocket, e.g., using ACLI:
#
#     acli -u "ws://localhost:3000/cable?user_id=431" -c ChatChannel --channel-params id:42
#
# Then, you can publish a message via cURL:
#
#     curl -X POST -H Content-Type:application/json -d '{"message":"hello!"}' http://localhost:3000/rooms/42/messages
#
# You should see it delivered to both clients!
#
gemfile(true) do
	gem "rails", github: "palkan/rails", branch: "refactor/action-cable-server-adapterization"
	gem "rackup"
	gem "falcon"
	
	gem "console-adapter-rails"
	gem "async-cable", path: "./"
end

require "action_controller/railtie"
require "action_cable/engine"

# config/application.rb
class App < Rails::Application
	config.root = __dir__
	config.eager_load = false

	config.load_defaults 7.1
	config.secret_key_base = "i_am_a_secret"
	config.hosts = []
	config.action_cable.disable_request_forgery_protection = true

	routes.append do
		mount Async::Cable::Middleware.new => "/cable", :internal => true
	end
end

# Define Action Cable subscription adapter
# Mark it is loaded to pass the `require ...` in the `#pubsub_adapter` method.
# TODO: Make it possible to provide adapter class directly.
$LOADED_FEATURES << "action_cable/subscription_adapter/iodine"

module ActionCable
	module SubscriptionAdapter
		class Iodine < Base
			def broadcast(channel, payload)
				::Iodine.publish(channel, payload)
			end
		end
	end
end

# Configure Action Cable
ActionCable.server.config.cable = {
	"adapter" => "async"
}

module Async
	module Cable
		class Connection
			attr_reader :logger, :request, :protocol, :server
			private attr_reader :sse, :coder, :connection, :buffer, :connected
			alias_method :connected?, :connected

			delegate :env, to: :request
			delegate :worker_pool, to: :server

			def initialize(server, request, websocket, coder: ActiveSupport::JSON, logger: Rails.logger)
				@protocol = "async-cable-v1"
				@server = server
				@logger = logger
				@request = request
				@coder = coder
				@websocket = websocket
				@connection = server.config.connection_class.call.new(server, self)
				@buffer = ::Thread::Queue.new
				@connected = true
			end

			def process
				loop do
					# Timeout must be greater then the heartbeat interval
					data = buffer.pop(timeout: 5)
					if data
						perform_transmit(data)
					else
						raise "No heartbeat received from client for 5 seconds, closing connection."
					end
				end
			end

			def transmit(data)
				return unless connected?
				buffer << data
			end

			def perform_transmit(data)
				sse.write(coder.encode(data))
			end

			def close
				@connected = false
				sse.close
			end

			def receive(message) # :nodoc:
				payload = coder.decode(message)
				connection.handle_incoming(payload)
			end

			def handle_open
				connection.handle_open
				server.add_connection(connection)
			end

			def handle_close
				server.remove_connection(connection)
				connection.handle_close
			end

			def perform_work(receiver, method_name, *)
				worker_pool.async_invoke(receiver, method_name, *, connection: self)
			end
		end

		class EventsController < ActionController::Base
			def index
				self.repsonse = Async::WebSocket::Adapter::Rails.new(request, handler: Connection) do |connection|
					connection.run!as
				end
			end
		end
	end
end

module ApplicationCable
	class Connection < ActionCable::Connection::Base
		identified_by :user_id

		def connect
			return reject_unauthorized_connection unless request.params[:user_id].present?

			self.user_id = request.params[:user_id]
			logger.debug "User connected via #{socket.protocol}: #{user_id}"
		end
	end

	class Channel < ActionCable::Channel::Base
	end
end

class ChatChannel < ApplicationCable::Channel
	def subscribed
		stream_from room_stream
	end

	def speak(data)
		ActionCable.server.broadcast room_stream, {text: data["text"]}
	end

	private

	def room_stream = "chat/#{params[:id]}"
end

class MessagesController < ActionController::Base
	protect_from_forgery with: :null_session

	def create
		text = params.require(:message)
		room_id = params[:room_id]

		ActionCable.server.broadcast "chat/#{room_id}", {text:}
	end
end

Rails.application.initialize!

require "rackup/handler/falcon"
Rackup::Handler::Falcon.run(Rails.application, Port: 3000)
