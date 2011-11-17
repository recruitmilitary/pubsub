require 'pubsub'

describe PubSub do
  it 'publishes and subscribes' do
    incoming = nil

    PubSub.subscribe("rm.bounces", "test-bounces") do |payload|
      incoming = payload
    end

    PubSub.publish("rm.bounces", :email => "a@a.com")

    # I really have no idea what I'm doing here, but it seems to work
    # so I'm going to roll with it.
    t = Thread.new { sleep 0.1; PubSub.stop }
    PubSub.run
    t.join

    incoming.should == { 'email' => 'a@a.com' }
  end
end
