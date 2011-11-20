require 'pubsub/version'

require 'amqp'
require 'bunny'
require 'multi_json'

# Public: Various methods useful for performing publish and subscribe
# via RabbitMQ.
#
# Examples
#
#   PubSub.subscribe("some.exchange_name", "queue_name") do |payload|
#     puts payload.inspect
#   end
#
#   PubSub.publish("some.exchange_name", :foo => :bar)
#
#   PubSub.run
#
#   PubSub will receive the JSON payload and print it to stdout.
#
#   {"foo"=>"bar"}
module PubSub
  extend self

  autoload :Subscription, 'pubsub/subscription'

  # Public: Set the AMQP URL for PubSub to connect to.
  #
  # Examples
  #
  #   PubSub.amqp_url = "amqp://user:password@rabbithost/"
  #
  # Returns nothing.
  attr_writer :amqp_url

  # Public: Returns the current amqp_url
  def amqp_url
    @amqp_url ||= ENV['AMQP_URL'] || 'amqp://guest:guest@localhost:5672/'
  end

  # Public: Sets the error handler
  def error_handler(&block)
    @error_handler = block
  end

  # Set the default error handler
  PubSub.error_handler do |error, queue, message, headers|
    raise e
  end

  # Public: Handles an error when they occur.  The default error
  # handler just raises the exception.
  def handle_error(error, queue, message, headers)
    @error_handler.call(error, queue, message, headers)
  end

  # Public: Sets the logger
  def logger(&block)
    @logger = block
  end

  # Set the default logger to ignore messages
  PubSub.logger {}

  # Public: Send a message to the logger
  def log(message)
    @logger.call(message)
  end

  # Public: Starts the EventMachine and AMQP loop waiting for work to
  # be processed.
  #
  # Returns nothing.
  def run
    register_signal_handlers

    AMQP.start(config) do |connection|
      channel = AMQP::Channel.new(connection)

      process_subscriptions(channel)
    end
  end

  # Public: Stops the EventMachine and AMQP run loop
  #
  # Returns nothing.
  def stop
    AMQP.stop { EventMachine.stop }
  end

  # Internal: Stop the EventMachine and AMQP run loop when INT or TERM
  # signals are received.
  #
  # Returns nothing.
  def register_signal_handlers
    ['INT', 'TERM'].each do |signal|
      Signal.trap(signal) {
        PubSub.stop
      }
    end
  end

  # Public: Publish a message to RabbitMQ for processing in a worker.
  #
  # exchange_name - The name of the exchange to send the payload to.
  # payload       - The payload to be encoded as JSON and delivered to
  #                 the exchange.
  #
  # Returns nothing.
  def publish(exchange_name, payload)
    encoded  = encode(payload)

    connect do |bunny|
      exchange = bunny.exchange(exchange_name, :type => :fanout)
      exchange.publish(encoded)
    end
  end

  # Public: Returns the hash of configuration options.
  def config
    uri = URI.parse(amqp_url)
    {
      :vhost => uri.path,
      :host  => uri.host,
      :user  => uri.user,
      :port  => (uri.port || 5672),
      :pass  => uri.password
    }
  rescue => e
    raise("invalid AMQP_URL: #{uri.inspect} (#{e})")
  end

  # Internal: An instance of Bunny to use for synchronously publishing
  # messages to an exchange.
  #
  # Returns a Bunny instance.
  def connect
    bunny = Bunny.new(config.merge(:logging => false))
    bunny.start
    yield bunny if block_given?
    bunny.stop
  end

  # Public: Configure a block to be run when a message is received for
  # a specific exchange and queue.
  #
  # exchange_name - The name of the exchange that will receive the message.
  # queue_name    - The name of the queue that will receive the message.
  # action        - A block to be run when a message is received.
  #
  # Returns nothing.
  def subscribe(exchange_name, queue_name, &action)
    subscriptions << Subscription.new(exchange_name, queue_name, &action)
  end

  # Internal: Loop through each subscription processing it against the
  # channel.
  #
  # Returns nothing.
  def process_subscriptions(channel)
    subscriptions.each do |subscription|
      bounces = channel.fanout(subscription.exchange_name)

      channel.queue(subscription.queue_name, :auto_delete => false,
                                             :durable     => true).
        bind(bounces).subscribe(:ack => true) do |metadata, payload|
        begin
          parsed = decode(payload)
          subscription.action.call(parsed)
        rescue => e
          handle_error(e, @queue_name, payload, metadata)
        end

        metadata.ack
      end
    end
  end

  # Internal: Return a collection of current subscriptions.
  def subscriptions
    @subscriptions ||= []
  end

  # Internal: Encode a payload as JSON
  def encode(payload)
    MultiJson.encode(payload)
  end

  # Internal: Decode a JSON payload
  def decode(payload)
    MultiJson.decode(payload)
  end

end
