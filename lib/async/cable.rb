# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024, by Samuel Williams.

require_relative 'cable/version'

begin
	require "rails/railtie"
	require_relative "cable/railtie"
rescue LoadError
	# Ignore.
end
