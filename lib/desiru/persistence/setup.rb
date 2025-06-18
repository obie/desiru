# frozen_string_literal: true

require 'sequel'

module Desiru
  module Persistence
    # Setup and initialization for persistence layer
    module Setup
      @initialized = false

      def self.initialized?
        @initialized
      end

      def self.initialize!(db_connection)
        # Always reinitialize if the database connection has changed
        return if @initialized && Sequel::Model.db == db_connection

        # Ensure we have a valid connection
        raise 'Database connection required' unless db_connection

        # Create the base model with a specific database
        Sequel::Model.db = db_connection

        # Define the base model class
        base_class = Class.new(Sequel::Model) do
          # This is an abstract model - no table
          def self.inherited(subclass)
            super
            subclass.plugin :timestamps, update_on_create: true
            subclass.plugin :json_serializer
            subclass.plugin :validation_helpers
          end

          # Helper to create JSON columns that work across databases
          def self.json_column(name)
            case db.adapter_scheme
            when :postgres
              # PostgreSQL has native JSON support
              nil # No special handling needed
            when :sqlite, :mysql, :mysql2
              # SQLite and MySQL store JSON as text
              plugin :serialization
              serialize_attributes :json, name
            end
          end
        end

        # Make it unrestricted so it doesn't look for a table
        base_class.unrestrict_primary_key

        # Set the Base constant
        Models.send(:remove_const, :Base) if Models.const_defined?(:Base)
        Models.const_set(:Base, base_class)

        # Remove existing model constants to force reload
        %i[ModuleExecution ApiRequest OptimizationResult TrainingExample JobResult].each do |model|
          Models.send(:remove_const, model) if Models.const_defined?(model)
        end

        # Now load all model classes - use load instead of require to force re-execution
        load File.expand_path('models/module_execution.rb', __dir__)
        load File.expand_path('models/api_request.rb', __dir__)
        load File.expand_path('models/optimization_result.rb', __dir__)
        load File.expand_path('models/training_example.rb', __dir__)
        load File.expand_path('models/job_result.rb', __dir__)

        # Setup repositories
        require_relative 'repository'
        Repository.setup!

        @initialized = true
        true
      end
    end
  end
end
