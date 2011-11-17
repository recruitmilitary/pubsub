# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "pubsub/version"

Gem::Specification.new do |s|
  s.name        = "pubsub"
  s.version     = PubSub::VERSION
  s.authors     = ["Michael Guterl"]
  s.email       = ["michael@diminishing.org"]
  s.homepage    = ""
  s.summary     = %q{Simple PubSub wrapper for RabbitMQ}
  s.description = %q{Simple PubSub wrapper for RabbitMQ}

  s.rubyforge_project = "pubsub"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency "rspec"
  s.add_runtime_dependency "amqp", "~> 0.8.3"
  s.add_runtime_dependency "bunny", "~> 0.7.8"
  s.add_runtime_dependency "multi_json", "~> 1.0.3"

end
