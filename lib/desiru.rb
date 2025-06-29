# frozen_string_literal: true

require 'forwardable'
require 'singleton'

# Main namespace for Desiru - Declarative Self-Improving Ruby
module Desiru
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

    def logger
      configuration.logger
    end
  end
end

# Core components
require_relative 'desiru/version'
require_relative 'desiru/errors'
require_relative 'desiru/configuration'
require_relative 'desiru/core'
require_relative 'desiru/field'
require_relative 'desiru/signature'
require_relative 'desiru/assertions'
require_relative 'desiru/module'
require_relative 'desiru/program'
require_relative 'desiru/registry'
require_relative 'desiru/cache'

# Model adapters
require_relative 'desiru/models/base'
require_relative 'desiru/models/anthropic'
require_relative 'desiru/models/open_ai'
require_relative 'desiru/models/open_router'

# Built-in modules
require_relative 'desiru/modules/predict'
require_relative 'desiru/modules/chain_of_thought'
require_relative 'desiru/modules/retrieve'
require_relative 'desiru/modules/react'
require_relative 'desiru/modules/program_of_thought'
require_relative 'desiru/modules/multi_chain_comparison'
require_relative 'desiru/modules/best_of_n'
require_relative 'desiru/modules/majority'

# Optimizers
require_relative 'desiru/optimizers/base'
require_relative 'desiru/optimizers/bootstrap_few_shot'
require_relative 'desiru/optimizers/knn_few_shot'
require_relative 'desiru/optimizers/copro'
require_relative 'desiru/optimizers/mipro_v2'

# Background jobs
require_relative 'desiru/async_capable'
require_relative 'desiru/async_status'
require_relative 'desiru/jobs/base'
require_relative 'desiru/jobs/async_predict'
require_relative 'desiru/jobs/batch_processor'

# API integrations
require_relative 'desiru/api'
require_relative 'desiru/jobs/optimizer_job'

# Persistence layer
require_relative 'desiru/persistence'

# GraphQL integration (optional, requires 'graphql' gem)
begin
  require 'graphql'
  require_relative 'desiru/graphql/schema_generator'
rescue LoadError
  # GraphQL integration is optional
end

# Include Traceable in Module class after everything is loaded
module Desiru
  class Module
    include Core::Traceable
  end
end
