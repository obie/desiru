# frozen_string_literal: true

require 'mock_redis'

module RedisMockHelper
  def self.included(base)
    base.let(:mock_redis_instance) { MockRedis.new }

    base.before do
      # Mock Redis.new to return our MockRedis instance
      allow(Redis).to receive(:new).and_return(mock_redis_instance)

      # Mock AsyncStatus to use our mock Redis by mocking the redis instance variable
      if defined?(Desiru::AsyncStatus)
        allow_any_instance_of(Desiru::AsyncStatus).to receive(:fetch_status).and_wrap_original do |method, *args|
          instance = method.receiver
          instance.instance_variable_set(:@redis, mock_redis_instance) unless instance.instance_variable_get(:@redis)
          method.call(*args)
        end

        allow_any_instance_of(Desiru::AsyncStatus).to receive(:fetch_result).and_wrap_original do |method, *args|
          instance = method.receiver
          instance.instance_variable_set(:@redis, mock_redis_instance) unless instance.instance_variable_get(:@redis)
          method.call(*args)
        end
      end

      # Mock AsyncCapable module only if it has redis method
      if defined?(Desiru::AsyncCapable) && Desiru::AsyncCapable.instance_methods.include?(:redis)
        allow_any_instance_of(Desiru::AsyncCapable).to receive(:redis).and_return(mock_redis_instance)
      end

      # For Jobs::Base, ensure it uses mocked Redis
      if defined?(Desiru::Jobs::Base)
        allow_any_instance_of(Desiru::Jobs::Base).to receive(:redis).and_return(mock_redis_instance)
      end

      # Clear mock redis before each test
      mock_redis_instance.flushdb
    end
  end

  # Helper method to get the current mock redis instance for assertions
  def mock_redis
    mock_redis_instance
  end
end
