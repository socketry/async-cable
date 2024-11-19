#!/usr/bin/env ruby
# frozen_string_literal: true

require "iodine"

require_relative "../application"

module ActionCable
	module SubscriptionAdapter
		class Iodine < Base
			def initialize(*)
				super
				@redis = ::Redis.new
			end

			def broadcast(channel, payload)
				# FIXME: Doesn't publis to Redis when executed outside of the Iodine server
				# (e.g., from AnyT tests)
				# ::Iodine.publish(channel, payload)
				@redis.publish(channel, payload)
			end
		end
	end

	module Iodine
		# Middleware is a Rack middleware that upgrades HTTP requests to WebSocket connections
		class Middleware
			attr_reader :server

			delegate :logger, to: :server

			def initialize(_app, server: ::ActionCable.server)
				@server = server
			end

			def call(env)
				if env["rack.upgrade?"] == :websocket && server.allow_request_origin?(env)
					subprotocol = select_protocol(env)
					
					env["rack.upgrade"] = Socket.new(server, env, protocol: subprotocol)
					logger.debug "[Iodine] upgrading to WebSocket [#(subprotocol)]"
					[101, {"Sec-Websocket-Protocol" => subprotocol}, []]
				else
					[404, {}, ["Not Found"]]
				end
			end

			private

			def select_protocol(env)
				supported_protocols = ::ActionCable::INTERNAL[:protocols]
				request_protocols = env["HTTP_SEC_WEBSOCKET_PROTOCOL"]
				if !request_protocols
					logger.error("No Sec-WebSocket-Protocol provided")
					return
				end

				request_protocols = request_protocols.split(/,\s?/) if request_protocols.is_a?(String)
				subprotocol = request_protocols.detect { _1.in?(supported_protocols) }

				logger.error("Unsupported protocol: #{request_protocols}") unless subprotocol
				subprotocol
			end
		end

		# This is a server wrapper to support Iodine native pub/sub
		class Server < SimpleDelegator
			# This is a pub/sub implementation that uses
			# Iodine client to subscribe to channels.
			# For that, we need an instance of Iodine::Connection to call #subscribe/#unsubscribe on.
			class PubSubInterface < Data.define(:socket)
				delegate :iodine_client, to: :socket, allow_nil: true

				def subscribe(channel, handler, on_success = nil)
					return unless iodine_client

					# NOTE: Iodine doesn't allow having different handlers for the same channel name,
					# so, having multiple channels listening to the same stream is currently not possible.
					#
					# We can create internal, server-side, subscribers to handle original broadcast requests
					# and then forward them to the specific identifiers. SubsriberMap can be reused for that.
					iodine_client.subscribe(to: channel, handler: proc { |_, msg| handler.call(msg) })
					on_success&.call
				end

				def unsubscribe(channel, _handler)
					iodine_client&.unsubscribe(channel)
				end
			end

			attr_accessor :pubsub

			def self.for(server, socket)
				new(server).tap do |srv|
					srv.pubsub = PubSubInterface.new(socket)
				end
			end
		end

		# Socket wraps Iodine client and provides ActionCable::Server::_Socket interface
		class Socket
			private attr_reader :server, :coder, :connection
			attr_reader :client

			alias_method :iodine_client, :client

			delegate :worker_pool, to: :server

			def initialize(server, env, protocol: nil, coder: ActiveSupport::JSON)
				@server = server
				@coder = coder
				@env = env
				@logger = server.new_tagged_logger { request }
				@protocol = protocol

				server = Server.for(server, self)
				@connection = server.config.connection_class.call.new(server, self)

				# Underlying Iodine client is set on connection open
				@client = nil
			end

			#== Iodine callbacks ==
			def on_open(conn)
				logger.debug "[Iodine] connection opened"

				@client = conn
				connection.handle_open

				server.setup_heartbeat_timer
				server.add_connection(connection)
			end

			def on_message(_conn, msg)
				logger.debug "[Iodine] incoming message: #{msg}"
				connection.handle_incoming(coder.decode(msg))
			end

			def on_close(conn)
				logger.debug "[Iodine] connection closed"
				server.remove_connection(connection)
				connection.handle_close
			end

			def on_shutdown(conn)
				logger.debug "[Iodine] connection shutdown"
				conn.write(
										coder.encode({
												type: :disconnect,
												reason: ::ActionCable::INTERNAL[:disconnect_reasons][:server_restart],
												reconnect: true
										})
								)
			end

			#== ActionCable socket interface ==
			attr_reader :env, :logger, :protocol

			def request
				# Copied from ActionCable::Server::Socket#request
				@request ||= begin
					environment = Rails.application.env_config.merge(env) if defined?(Rails.application) && Rails.application
					ActionDispatch::Request.new(environment || env)
				end
			end

			def transmit(data)
				client&.write(coder.encode(data))
			end

			def close = client&.close

			def perform_work(receiver, method_name, *args)
				worker_pool.async_invoke(receiver, method_name, *args, connection: self)
			end
		end
	end
end

Iodine::PubSub.default = Iodine::PubSub::Redis.new("redis://localhost:6379")
ActionCable.server.config.pubsub_adapter = "ActionCable::SubscriptionAdapter::Iodine"

class BenchmarkServer
	def self.run!
		app = Rack::Builder.new do
			map "/cable" do
				use ActionCable::Iodine::Middleware
				run(proc { |_| [404, {"Content-Type" => "text/plain"}, ["Not here"]] })
			end
		end

		Iodine::DEFAULT_SETTINGS[:port] = 8080
		Iodine.threads = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
		Iodine.workers = ENV.fetch("WEB_CONCURRENCY", 4).to_i

		Iodine.listen service: :http, handler: app
		Iodine.start
	end
end

BenchmarkServer.run!
