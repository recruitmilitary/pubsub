class PubSub

  class Subscription
    attr_reader :exchange_name, :exchange_opts, :queue_opts, :subscribe_opts, :bind_opts, :queue_name, :action, :decoder

    def initialize(queue_name, options = {}, &action)
      @exchange_opts = options.delete(:exchange) || {}
      @exchange_name = @exchange_opts.delete(:name)
      @queue_opts = options.delete(:queue) || {}
      @subscribe_opts = options.delete(:subscribe) || {}
      @subscribe_opts[:manual_ack] = true unless @subscribe_opts.has_key?(:manual_ack)
      @bind_opts = options.delete(:bind) || {}
      @queue_name    = queue_name
      @decoder       = options[:decoder]
      @action        = action
    end
  end

end
