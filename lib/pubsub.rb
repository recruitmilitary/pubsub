require 'pubsub/version'

require 'bunny'
require 'multi_json'

require 'pubsub/config'
require 'pubsub/subscription'

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
class PubSub
  attr_reader :connection_opts, :connection, :channel

  class << self
    def configure
      yield Config
    end
  end

  def initialize(connection_and_opts = {})
    exchange = connection_and_opts.delete(:exchange) || {}
    @default_exchange_name = exchange.delete(:name)
    @default_exchange_opts = exchange

    @connection_opts = Config.connection_hash.merge(connection_and_opts)
    @exchanges = {}

    self.decoder = ->(payload, metadata) {decode(payload)}
    self.logger {}
    self.error_handler do |error, queue, message, metadata, delivery_info|
      raise error
    end
  end

  def start
    @connection = Bunny.new(connection_opts)
    @connection.start
    register_signal_handlers

    @channel = @connection.create_channel
  end

  def change_default_exchange(name, opts = {})
    @default_exchange_name = name
    @default_exchange_opts = Config.default_exchange_opts.merge(opts)
  end

  def default_exchange
    @exchanges[default_exchange_name] ||= channel.exchange(default_exchange_name, default_exchange_opts) if default_exchange_name
  end

  def default_exchange_name
    @default_exchange_name
  end

  def default_exchange_opts
    @default_exchange_opts
  end

  def decoder=(d)
    @decoder = d
  end

  def decoder
    @decoder
  end

  # Public: Sets the error handler
  def error_handler(&block)
    @error_handler = block
  end

  # Public: Handles an error when they occur.  The default error
  # handler just raises the exception.
  def handle_error(error, queue, message, metadata, delivery_info)
    @error_handler.call(error, queue, message, metadata, delivery_info)
  end

  # Public: Sets the logger
  def logger(&block)
    @logger = block
  end

  # Public: Send a message to the logger
  def log(message)
    @logger.call(message)
  end

  def exchange(name, opts = {})
    if name
      opts = Config.default_exchange_opts.merge(opts)
      @exchanges[name] ||= channel.exchange(name, opts)
    else
      default_exchange
    end
  end

  # Public: Starts the EventMachine and AMQP loop waiting for work to
  # be processed.
  #
  # Returns nothing.
  def run
    subscriptions.each do |sub|
      ex = exchange(sub.exchange_name, sub.exchange_opts)
      channel.queue(sub.queue_name, sub.queue_opts).
        bind(ex, sub.bind_opts).subscribe(sub.subscribe_opts) do |delivery_info, metadata, payload|
        begin
          decoded = (sub.decoder || decoder).call(payload, metadata)
          sub.action.call(delivery_info, metadata, decoded)
        rescue => e
          handle_error(e, sub.queue_name, payload, metadata, delivery_info)
        end
      end
    end
  end

  # Public: Stops the bunny conection and channel
  #
  # Returns nothing.
  def stop
    connection.close if connection
  end

  # Internal: Stop the Bunny connection and channel when INT or TERM
  # signals are received.
  #
  # Returns nothing.
  def register_signal_handlers
    ['INT', 'TERM'].each do |signal|
      Signal.trap(signal) {
        stop
      }
    end
  end

  # Public: Accumulate all messages that are published within a block, and only 
  # publish them after successful completion of the block.
  #
  # Returns array of delivered payloads
  def transaction(&block)
    # No transaction nesting
    return @transacted_messages if !@transacted_messages.nil?

    @transacted_messages = []
    yield

    # no errors, so now we'll publish
    @transacted_messages.map do |ex, payload, metadata|
      ex.publish(payload, metadata)
      payload
    end

  ensure
    @transacted_messages = nil
  end

  # Public: Publish a message to RabbitMQ for processing in a worker.
  #
  # exchange_name - The name of the exchange to send the payload to.
  # payload       - The payload to be encoded as JSON and delivered to
  #                 the exchange.
  #
  # Returns nothing.
  def publish(payload, metadata = {})
    exchange_opts = metadata.delete(:exchange) || {}
    encoded = String===payload ? payload : encode(payload)

    ex = exchange(exchange_opts.delete(:name), exchange_opts)
    if @transacted_messages.nil?
      ex.publish(encoded, metadata)
    else
      @transacted_messages << [ex, encoded, metadata]
    end

    encoded
  end

  def publish_topic(payload, routing_key, metadata = {})
    metadata[:routing_key] = routing_key
    publish(payload, metadata)
  end

  # Public: Configure a block to be run when a message is received for
  # a specific exchange and queue.
  #
  # exchange_name - The name of the exchange that will receive the message.
  # queue_name    - The name of the queue that will receive the message.
  # action        - A block to be run when a message is received.
  #
  # Returns nothing.
  def subscribe(queue_name, options = {}, &action)
    options[:exchange] = {name: default_exchange_name}.merge(Config.default_exchange_opts.merge(options[:exchange] ||= {}))
    options[:queue] = Config.default_queue_opts.merge(options[:queue] ||= {})
    subscriptions << Subscription.new(queue_name, options, &action)
  end

  def subscribe_topic(queue_name, routing_key, options = {}, &action)
    (options[:bind] ||= {}).merge!(routing_key: routing_key)
    (options[:exchange] ||= {}).merge!(type: :topic)
    subscribe(queue_name, options, &action)
  end

  private
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
