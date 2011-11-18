module PubSub

  class Subscription
    attr_reader :exchange_name, :queue_name, :action

    def initialize(exchange_name, queue_name, &action)
      @exchange_name = exchange_name
      @queue_name    = queue_name
      @action        = action
    end
  end

end
