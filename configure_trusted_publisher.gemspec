# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "configure_trusted_publisher/version"

Gem::Specification.new do |spec|
  spec.name          = "configure_trusted_publisher"
  spec.version       = ConfigureTrustedPublisher::VERSION
  spec.authors       = ["Samuel Giddins"]
  spec.email         = ["segiddins@segiddins.me"]

  spec.summary       = "A small CLI to automate the process of configuring a trusted publisher for a gem."
  spec.homepage      = "https://github.com/rubygems/configure_trusted_publisher"
  spec.license       = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.required_ruby_version = ">= 3.3"
  spec.required_rubygems_version = ">= 3.5"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = IO.popen(["git", "-C", __dir__, "ls-files", "-z"], &:read).split("\x0").reject do |f|
    f.start_with?(".") ||
      %W[#{File.basename(__FILE__)} Gemfile Gemfile.lock Rakefile].include?(f) ||
      f.match(%r{^(test|spec|features|bin|\.github)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "bundler", "~> 2.5"
  spec.add_runtime_dependency "command_kit", "~> 0.5.5"

  spec.metadata["rubygems_mfa_required"] = "true"
end
