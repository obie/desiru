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
        return if @initialized

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

        # Now load all model classes
        require_relative 'models/module_execution'
        require_relative 'models/api_request'
        require_relative 'models/optimization_result'
        require_relative 'models/training_example'

        # Setup repositories
        require_relative 'repository'
        Repository.setup!

        @initialized = true
        true
      end
    end
  end
end
