require 'pubsub'

describe PubSub do
  def run
    # I really have no idea what I'm doing here, but it seems to work
    # so I'm going to roll with it.
    t = Thread.new { sleep 0.1; PubSub.stop }
    PubSub.run
    t.join
  end

  it 'publishes and subscribes' do
    incoming = nil

    PubSub.subscribe("pubsub.test", "test") do |payload|
      incoming = payload
    end

    PubSub.publish("pubsub.test", :email => "a@a.com")
    run

    incoming.should == { 'email' => 'a@a.com' }
  end

  it 'allows custom error handlers' do
    error = []
    PubSub.error_handler { |*args| error = args }

    PubSub.publish("pubsub.test", "notjson")
    run

    exception, queue, message, headers = error

    exception.should be_an_instance_of MultiJson::DecodeError
    exception.message.should == 'unexpected "notjson"'
    queue.should == nil
    message.should == '"notjson"'
    headers.should be_an_instance_of AMQP::Header
  end
end
