# frozen_string_literal: true

require 'forwardable'
require 'singleton'

# Main namespace for Desiru - Declarative Self-Improving Ruby
module Desiru
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class SignatureError < Error; end
  class ModuleError < Error; end
  class ValidationError < Error; end
  class TimeoutError < Error; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

# Core components
require_relative 'desiru/version'
require_relative 'desiru/configuration'
require_relative 'desiru/field'
require_relative 'desiru/signature'
require_relative 'desiru/module'
require_relative 'desiru/program'
require_relative 'desiru/registry'
require_relative 'desiru/cache'

# Model adapters
require_relative 'desiru/models/base'
require_relative 'desiru/models/raix_adapter'

# Built-in modules
require_relative 'desiru/modules/predict'
require_relative 'desiru/modules/chain_of_thought'
require_relative 'desiru/modules/retrieve'

# Optimizers
require_relative 'desiru/optimizers/base'
require_relative 'desiru/optimizers/bootstrap_few_shot'

# Background jobs
require_relative 'desiru/jobs/base'
require_relative 'desiru/jobs/async_predict'
require_relative 'desiru/jobs/batch_processor'
require_relative 'desiru/jobs/optimizer_job'

# GraphQL integration (optional, requires 'graphql' gem)
begin
  require 'graphql'
  require_relative 'desiru/graphql/schema_generator'
rescue LoadError
  # GraphQL integration is optional
end
