# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2023-2026, by Samuel Williams.

source "https://rubygems.org"

gemspec

# The `next` branch targets Rails main, which now includes the
# `ActionCable::Server::Socket` abstraction (rails/rails#50979) that
# previously required actioncable-next.
gem "rails", github: "rails/rails", branch: "main"

gem "async"

gem "agent-context"

group :maintenance, optional: true do
	gem "bake-gem"
	gem "bake-modernize"
	gem "bake-releases"
	
	gem "decode"
	
	gem "utopia-project"
end

group :test do
	gem "sus"
	gem "covered"
	
	gem "rubocop"
	gem "rubocop-md"
	gem "rubocop-rails-omakase"
	gem "rubocop-socketry"
	
	gem "sus-fixtures-async-http"
	gem "sus-fixtures-console"
	
	gem "bake-test"
	gem "bake-test-external"
	
	gem "redis"
end
