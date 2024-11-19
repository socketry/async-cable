# frozen_string_literal: true
# Released under the MIT License.
# Copyright, 2023-2024, by Samuel Williams.

source "https://rubygems.org"

gemspec

group :maintenance, optional: true do
	gem "bake-gem"
	gem "bake-modernize"
	
	gem "utopia-project"
end

group :test do
	gem "sus"
	gem "covered"
	gem "decode"
	gem "rubocop"
	
	gem "sus-fixtures-async-http"
	gem "sus-fixtures-console"
	
	gem "async-websocket"
	
	gem "bake-test"
	gem "bake-test-external"
	
	gem "redis"
end
