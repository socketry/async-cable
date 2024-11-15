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
	
	spec.metadata = {
		"documentation_uri" => "https://socketry.github.io/async-cable/",
		"source_code_uri" => "https://github.com/socketry/async-cable",
	}
	
	spec.files = Dir["{lib}/**/*", "*.md", base: __dir__]
	
	spec.required_ruby_version = ">= 3.1"
	
	spec.add_dependency "actioncable-next"
	spec.add_dependency "async", "~> 2.9"
	spec.add_dependency "async-websocket"
end
