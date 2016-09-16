require 'pubsub'
require 'pry'

# Sleep statements are required because Bunny runs in a separate thread, and 
# if messages publish before subscribe Rabbit discards it. So the only options  
# is to subscribe, publish, sleep/receive, then test.
#
# The alternative is to do expectations inside the block, but then there is no 
# way to ensure that the expectation was actually reached, and the spec will 
# pass regardless.
describe PubSub do
  let(:connect_opts) {
    if ENV['RABBITMQ_URL']
      PubSub::Config.amqp_url = ENV['RABBITMQ_URL']
      {}
    else
      {host: 'localhost', port: 5672}
    end
  }
  let(:pubsub) {ps = PubSub.new(connect_opts); ps.start; ps}

  def ack(di)
    di.channel.acknowledge(di.delivery_tag)
  end

  before do
    PubSub::Config.default_exchange_opts = {type: :fanout, durable: false, auto_delete: false}
    PubSub::Config.default_queue_opts = {durable: true, auto_delete: false}
    pubsub.change_default_exchange("pubsub.test")
  end

  after do
    #pubsub.stop
    pubsub.channel.consumers.values.each(&:cancel)
  end

  it 'publishes and subscribes' do
    incoming = nil

    pubsub.publish({email: 'a@a.com'})

    pubsub.subscribe("test", subscribe: {block: true, manual_ack: true}) do |di, metadata, payload|
      incoming = payload
      di.consumer.cancel
    end
    pubsub.run

    expect(incoming).to eq('email' => 'a@a.com')
  end

  it "defaults to persistent messages" do
    md = nil
    pubsub.publish({email: 'a@a.com'}, {headers: {}, content_type: 'application/json', timestamp: Time.now.to_i})

    pubsub.subscribe("test", subscribe: {block: true, manual_ack: true}) do |di, metadata, payload|
      md = metadata
      di.consumer.cancel
    end
    pubsub.run

    expect(md[:delivery_mode]).to eq(2)
  end

  it 'allows custom error handlers' do
    error = []
    pubsub.error_handler { |*args| error = args; args.last.consumer.cancel }

    pubsub.publish("notjson")
    pubsub.subscribe("test", subscribe: {block: true, manual_ack: true}) {|payload, md, di| }
    pubsub.run

    exception, queue, message, metadata, di = error

    expect(exception).to be_an_instance_of MultiJson::DecodeError
    expect(exception.message).to eq("795: unexpected token at 'notjson'")
    expect(queue).to eq("test")
    expect(message).to eq('notjson')
    expect(metadata).to be_an_instance_of Bunny::MessageProperties
    expect(di).to be_an_instance_of Bunny::DeliveryInfo
  end

  it "can defaults to manual acknowledgmet" do
    manual_ack = nil

    pubsub.publish({email: 'a@a.com'})

    pubsub.subscribe("test", subscribe: {block: true}) do |di, metadata, payload|
      manual_ack = di.consumer.manual_acknowledgement?
      ack(di)
      di.consumer.cancel
    end
    pubsub.run

    expect(manual_ack).to be(true)
  end

  it "properly changes the default exchange" do
    fanout_msg = nil
    topic_msg = nil

    pubsub.publish({a: 1}, exchange: {name: 'pubsub.test', type: :fanout})
    pubsub.publish({b: 2}, routing_key: 'stuff', exchange: {name: 'pubsub.topic', type: :topic})

    pubsub.subscribe("test", subscribe: {block: true, manual_ack: true}) do |di, metadata, payload|
      fanout_msg = payload
      di.consumer.cancel
    end

    pubsub.change_default_exchange('pubsub.topic', type: :topic)

    md = nil
    pubsub.subscribe_topic("pubsub.test.topic", "stuff", subscribe: {block: true, manual_ack: true}) do |di, metadata, payload|
      topic_msg = payload
      md = metadata
      di.consumer.cancel
    end
    
    pubsub.run

    expect(fanout_msg).to eq('a' => 1)
    expect(topic_msg).to eq('b' => 2)
  end

  it "uses a custom decoder" do
    decoded = nil
    custom_decoder = ->(payload, metadata) {'decoded'}
    pubsub.publish({email: 'a@a.com'})

    pubsub.subscribe("test", decoder: custom_decoder, subscribe: {block: true, manual_ack: true}) do |di, metadata, payload|
      decoded = payload
      di.consumer.cancel
    end
    pubsub.run

    expect(decoded).to eq('decoded')
  end

  describe '#change_default_exchange' do
    it "changes the default exchange name" do
      pubsub.change_default_exchange("pubsub.changed")
      expect(pubsub.default_exchange_name).to eq('pubsub.changed')
    end

    it "merges the exchange options with the default exchange options" do
      pubsub.change_default_exchange("pubsub.changed", type: :topic)
      expected = PubSub::Config.default_exchange_opts.merge(type: :topic)
      expect(pubsub.default_exchange_opts).to eq(expected)
    end
  end

  describe '#default_exchange' do
    it "creates an exchange using the default information if not present" do
      exchange_opts = {type: 'topic', auto_delete: true, durable: false}
      pubsub.change_default_exchange('pubsub.default_test', exchange_opts)
      expect(pubsub.channel).to receive(:exchange).with('pubsub.default_test', exchange_opts)
      pubsub.default_exchange
    end

    it "caches the exchange" do
      pubsub.default_exchange
      expect(pubsub.channel).not_to receive(:exchange)
      pubsub.default_exchange
    end
  end

  describe "#exchange" do
    context 'without name' do 
      it "returns the default exchange with no name given" do
        expect(pubsub.exchange(nil)).to eq(pubsub.default_exchange)
      end
    end

    context 'with name' do
      it "creates a new exchange with default options" do
        expected_opts = PubSub::Config.default_exchange_opts.merge(type: :topic)
        expect(pubsub.channel).to receive(:exchange).with('pubsub.exchange', expected_opts)
        pubsub.exchange('pubsub.exchange', type: :topic)
      end

      it "caches the exchange" do
        pubsub.exchange('pubsub.exchange', type: :topic)
        expect(pubsub.channel).not_to receive(:exchange)
        pubsub.exchange('pubsub.exchange', type: :topic)
      end
    end
  end

  describe '#transaction' do
    it "sends the messages if there is no error" do
      expect(pubsub.default_exchange).to receive(:publish).with('{"email":"a@a.com"}', {})
      expect(pubsub.default_exchange).to receive(:publish).with('{"name":"bob"}', {})

      pubsub.transaction do
        pubsub.publish({email: 'a@a.com'})
        pubsub.publish({name: 'bob'})
      end
    end

    it "can nest without problems" do
      expect(pubsub.default_exchange).to receive(:publish).with('{"email":"a@a.com"}', {})
      pubsub.transaction do
        pubsub.transaction do
          pubsub.publish({email: 'a@a.com'})
        end
      end
    end

    it "does not send any messages if there is an error" do
      expect(pubsub.default_exchange).not_to receive(:publish)

      begin
      pubsub.transaction do
        pubsub.publish({email: 'a@a.com'})
        raise StandardError
      end
      rescue
      end
    end
  end

  describe "#stop" do
    it "should stop the connection" do
      expect(pubsub.connection).to receive(:close)
      pubsub.stop
    end
  end
end
