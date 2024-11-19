#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../application"
require "anycable-rails"

ActionCable.server.config.cable = {"adapter" => "any_cable"}

class BenchmarkServer
	def self.run!
		require "anycable/cli"
		cli = AnyCable::CLI.new
		# We're already within the app context
		cli.define_singleton_method(:boot_app!) { }

		anycable_server_path = Rails.root.join("../bin/anycable-go")
		cli.run(["--server-command", "#{anycable_server_path} --host 0.0.0.0"])
	end
end

BenchmarkServer.run!
