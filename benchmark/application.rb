# frozen_string_literal: true

require "rails"
require "global_id"

require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"

# config/application.rb
class App < Rails::Application
  config.root = __dir__
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = false
  config.secret_key_base = "i_am_a_secret"

  config.hosts = []

  config.logger = ActiveSupport::Logger.new((ENV["LOG"] == "1") ? $stdout : IO::NULL)
  config.log_level = (ENV["LOG"] == "1") ? :debug : :fatal

  routes.append do
    # Add routes here if needed
  end
end

ActionCable.server.config.cable = {
  "adapter" => ENV.fetch("ACTION_CABLE_ADAPTER", "redis"),
  "url" => ENV["REDIS_URL"]
}
ActionCable.server.config.connection_class = -> { ApplicationCable::Connection }
ActionCable.server.config.disable_request_forgery_protection = true
ActionCable.server.config.logger = Rails.logger

# Load server configuration
require_relative "servers/#{$benchmark_server}" if defined?($benchmark_server)

Rails.application.initialize!

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :uid
  end

  class Channel < ActionCable::Channel::Base
  end
end

class BenchmarkChannel < ApplicationCable::Channel
  def subscribed
    stream_from "all#{stream_id}"
  end

  def echo(data)
    transmit data
  end

  def broadcast(data)
    ActionCable.server.broadcast "all#{stream_id}", data
    # data["action"] = "broadcastResult"
    # transmit data
  end

  private

  def stream_id
    params[:id] || ""
  end
end
