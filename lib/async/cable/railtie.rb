# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024, by Samuel Williams.

require_relative "server"

module Async
	module Cable
		# Rails integration that configures Action Cable to use {Server}.
		class Railtie < Rails::Railtie
			initializer "async.cable.configure_action_cable", before: "action_cable.set_configs" do |app|
				app.config.action_cable.server = Async::Cable::Server
			end
		end
	end
end
