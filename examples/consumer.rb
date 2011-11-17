require 'pubsub'

name = ARGV[0]

PubSub.subscribe("test.bounces", "bounces-#{name}") do |payload|
  puts "#{name} - #{payload['email']}"
end

PubSub.run
