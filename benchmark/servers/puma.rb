#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../application"

class BenchmarkServer
	def self.run!
		require "puma/cli"
		# cli = Puma::CLI.new(["-w", "#{ENV.fetch("WEB_CONCURRENCY", 4)}", "-t", "5", "-p", "8080", "-b", "tcp://0.0.0.0"])
		cli = Puma::CLI.new(["-t", "1", "-p", "8080", "-b", "tcp://0.0.0.0"])
		cli.instance_variable_get(:@conf).options[:app] = Rails.application
		cli.run
	end
end

BenchmarkServer.run!
