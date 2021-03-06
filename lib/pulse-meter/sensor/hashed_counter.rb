require 'json'

# Static hashed counter to count values by multiple keys
module PulseMeter
  module Sensor
    class HashedCounter < Counter

      # Increments counter value by 1 for given key
      # @param key [String] key to be incremented
      def incr(key)
        event({key => 1})
      end

      # Returs data stored in counter
      # @return [Hash]
      def value
        redis.
          hgetall(value_key).
          inject(Hash.new(0)) {|h, (k, v)| h[k] = v.to_i; h}
      end

      private

      # Processes events for multiple keys
      # @param data [Hash] hash where keys represent counter keys
      #   and values are increments for their keys
      def process_event(data)
        data.each_pair do |k, v|
          redis.hincrby(value_key, k, v.to_i)
          redis.hincrby(value_key, :total, v.to_i)
        end
      end

    end
  end
end
