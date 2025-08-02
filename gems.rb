# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2023-2024, by Samuel Williams.

source "https://rubygems.org"

gemspec

gem "async"

gem "agent-context"

group :maintenance, optional: true do
	gem "bake-gem"
	gem "bake-modernize"
	gem "bake-releases"
	
	gem "utopia-project"
end

group :test do
	gem "sus"
	gem "covered"
	gem "decode"
	
	gem "rubocop"
	gem "rubocop-rails-omakase"
	gem "rubocop-socketry"
	
	gem "sus-fixtures-async-http"
	gem "sus-fixtures-console"
	
	gem "async-websocket"
	
	gem "bake-test"
	gem "bake-test-external"
	
	gem "redis"
end
