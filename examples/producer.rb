require 'pubsub'

PubSub.publish("test.bounces", :email => "foo@bar.com")
