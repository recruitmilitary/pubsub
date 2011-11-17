module PubSub

  class Subscription
    def initialize(exchange_name, queue_name, &action)
      @exchange_name = exchange_name
      @queue_name    = queue_name
      @action        = action
    end

    def process(channel)
      bounces = channel.fanout(@exchange_name)

      channel.queue(@queue_name, :auto_delete => false, :durable => true).bind(bounces).subscribe(:ack => true) do |metadata, payload|
        begin
          parsed = PubSub.decode(payload)
          @action.call(parsed)
        rescue => e
          PubSub.handle_error(e)
        end

        metadata.ack
      end
    end
  end

end
