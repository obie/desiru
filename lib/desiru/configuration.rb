# frozen_string_literal: true

module Desiru
  # Global configuration for Desiru
  # Follows singleton pattern for service-oriented design
  class Configuration
    attr_accessor :default_model, :cache_enabled, :cache_ttl, :max_retries,
                  :retry_delay, :logger, :module_registry, :model_timeout,
                  :redis_url

    def initialize
      @default_model = nil
      @cache_enabled = true
      @cache_ttl = 3600 # 1 hour
      @max_retries = 3
      @retry_delay = 1
      @logger = default_logger
      @module_registry = Desiru::Registry.instance
      @model_timeout = 30
      @redis_url = nil # Defaults to REDIS_URL env var if not set
    end

    def validate!
      raise ConfigurationError, 'default_model must be set' unless default_model
      raise ConfigurationError, 'default_model must respond to :complete' unless default_model.respond_to?(:complete)
    end

    private

    def default_logger
      require 'logger'
      Logger.new($stdout).tap do |logger|
        logger.level = Logger::INFO
        logger.formatter = proc do |severity, datetime, _progname, msg|
          "[Desiru] #{datetime}: #{severity} -- #{msg}\n"
        end
      end
    end
  end
end
