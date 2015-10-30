class PubSub
  class Config
    class << self
      attr_writer :default_exchange_opts, :default_queue_opts, :default_subscribe_opts
      attr_writer :connection_hash

      def amqp_url=(url)
        parsed = AMQ::Settings.parse_amqp_url(url)
        @connection_hash = parsed
      end

      def connection_hash
        @connection_hash ||= {}
      end

      def default_exchange_opts
        @default_exchange_opts ||= {type: :fanout, durable: true, auto_delete: false}
      end

      def default_queue_opts
        @default_queue_opts ||= {durable: true, auto_delete: false}
      end

      def default_subscribe_opts
        @default_subscribe_opts ||= {}
      end
    end
  end
end
