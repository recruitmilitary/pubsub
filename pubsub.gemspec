# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "pubsub/version"

Gem::Specification.new do |s|
  s.name        = "pubsub"
  s.version     = PubSub::VERSION
  s.authors     = ["RecruitMilitary"]
  s.email       = ["support@recruitmilitary.com"]
  s.homepage    = ""
  s.summary     = %q{Simple PubSub wrapper for RabbitMQ}
  s.description = %q{Simple PubSub wrapper for RabbitMQ}

  s.rubyforge_project = "pubsub"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency "rspec"
  s.add_development_dependency "pry"
  s.add_development_dependency "pry-byebug"
  s.add_development_dependency "pry-stack_explorer"
  s.add_runtime_dependency "bunny", "~> 2.2.0"
  s.add_runtime_dependency "multi_json"

end
