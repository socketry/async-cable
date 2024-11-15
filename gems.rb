# Released under the MIT License.
# Copyright, 2023-2024, by Samuel Williams.

source "https://rubygems.org"

gem "rails"

group :maintenance, optional: true do
	gem "bake-gem"
	gem "bake-modernize"
end

group :test do
	gem "sus"
	gem "covered"
	gem "decode"
	gem "rubocop"
end
