# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024, by Samuel Williams.

require_relative "middleware"

module Async
	module Cable
		class Railtie < Rails::Railtie
			initializer "async.cable.configure_rails_initialization" do |app|
				$stderr.puts "Configuring Action Cable to use Async::Cable middleware..."
				app.middleware.use Async::Cable::Middleware
			end
		end
	end
end