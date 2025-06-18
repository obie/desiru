# frozen_string_literal: true

require_relative 'api/grape_integration'
require_relative 'api/sinatra_integration'
require_relative 'api/persistence_middleware'

module Desiru
  module API
    # Convenience method to create a new API integration
    # @param framework [Symbol] :grape or :sinatra (default: :grape)
    def self.create(framework: :grape, async_enabled: true, stream_enabled: false, &)
      klass = case framework
              when :grape
                GrapeIntegration
              when :sinatra
                SinatraIntegration
              else
                raise ArgumentError, "Unknown framework: #{framework}. Use :grape or :sinatra"
              end

      integration = klass.new(
        async_enabled: async_enabled,
        stream_enabled: stream_enabled
      )

      # Allow DSL-style configuration
      integration.instance_eval(&) if block_given?

      integration
    end

    # Convenience method to create a new Grape API (backward compatibility)
    def self.grape(async_enabled: true, stream_enabled: false, &)
      create(framework: :grape, async_enabled: async_enabled, stream_enabled: stream_enabled, &)
    end

    # Convenience method to create a new Sinatra API
    def self.sinatra(async_enabled: true, stream_enabled: false, &)
      create(framework: :sinatra, async_enabled: async_enabled, stream_enabled: stream_enabled, &)
    end
  end
end
