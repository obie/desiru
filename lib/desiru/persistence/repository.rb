# frozen_string_literal: true

require_relative 'repositories/base_repository'
require_relative 'repositories/module_execution_repository'
require_relative 'repositories/api_request_repository'
require_relative 'repositories/optimization_result_repository'
require_relative 'repositories/training_example_repository'
require_relative 'repositories/job_result_repository'

module Desiru
  module Persistence
    # Repository pattern for data access
    module Repository
      def self.setup!
        # Register all repositories
        Persistence.register_repository(:module_executions,
                                        Repositories::ModuleExecutionRepository.new)
        Persistence.register_repository(:api_requests,
                                        Repositories::ApiRequestRepository.new)
        Persistence.register_repository(:optimization_results,
                                        Repositories::OptimizationResultRepository.new)
        Persistence.register_repository(:training_examples,
                                        Repositories::TrainingExampleRepository.new)
        Persistence.register_repository(:job_results,
                                        Repositories::JobResultRepository.new)
      end
    end
  end
end
