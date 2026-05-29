# frozen_string_literal: true

require_relative "lib/async/cable/version"

Gem::Specification.new do |spec|
	spec.name = "async-cable"
	spec.version = Async::Cable::VERSION
	
	spec.summary = "An asynchronous adapter for ActionCable."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/release.pem")
	
	spec.homepage = "https://github.com/socketry/async-cable"
	
	spec.metadata = {
		"documentation_uri" => "https://socketry.github.io/async-cable/",
		"source_code_uri" => "https://github.com/socketry/async-cable",
	}
	
	spec.files = Dir["{lib}/**/*", "*.md", base: __dir__]
	
	spec.required_ruby_version = ">= 3.3"
	
	# Requires the `ActionCable::Server::Socket` abstraction introduced by
	# https://github.com/rails/rails/pull/50979 (Rails 8.1+).
	spec.add_dependency "actioncable", ">= 8.1.0.alpha"
	spec.add_dependency "async", "~> 2.9"
	spec.add_dependency "async-websocket"
end
