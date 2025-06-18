# frozen_string_literal: true

require 'desiru/persistence'
require 'desiru/persistence/setup'

module DatabaseHelper
  @connection_setup = false
  @mutex = Mutex.new

  class << self
    def setup_connection(force_new: false)
      @mutex.synchronize do
        # Force new connection for true isolation between test files
        if force_new || !@connection_setup || !Desiru::Persistence::Database.connection
          # Disconnect any existing connection
          begin
            Desiru::Persistence::Database.disconnect
          rescue StandardError
            nil
          end

          # Clear repository cache
          Desiru::Persistence.instance_variable_set(:@repositories, {})

          # Reset Setup if loaded - this is critical for forcing reinitialization
          Desiru::Persistence::Setup.instance_variable_set(:@initialized, false) if defined?(Desiru::Persistence::Setup)

          # Connect to in-memory database - each gets its own instance
          Desiru::Persistence::Database.connect('sqlite::memory:')
          Desiru::Persistence::Database.migrate!

          # Setup repositories after migration
          Desiru::Persistence::Repository.setup!

          @connection_setup = true
        end
      end
    end

    def clean_tables
      return unless Desiru::Persistence::Database.connection

      # Don't use a transaction since we're disabling foreign keys
      # Temporarily disable foreign key checks for cleaning
      if Desiru::Persistence::Database.connection.adapter_scheme == :sqlite
        Desiru::Persistence::Database.connection.run('PRAGMA foreign_keys = OFF')
      end

      begin
        # Get all table names to ensure we clean everything
        tables = Desiru::Persistence::Database.connection.tables

        # Delete all records from all tables in reverse order
        # The order matters for foreign key constraints when they're on
        %i[training_examples optimization_results module_executions api_requests job_results].each do |table|
          if tables.include?(table)
            count_before = Desiru::Persistence::Database.connection[table].count
            Desiru::Persistence::Database.connection[table].delete
            count_after = Desiru::Persistence::Database.connection[table].count

            if count_after > 0
              puts "ERROR: Failed to clean #{table}! Had #{count_before}, now has #{count_after}"
            elsif ENV['DEBUG_DB'] && count_before > 0
              puts "Cleaned #{count_before} records from #{table}"
            end
          end
        rescue Sequel::DatabaseError => e
          # Table might not exist yet, which is fine
          puts "Warning: Could not clean table #{table}: #{e.message}" if ENV['DEBUG']
        end
      ensure
        # Always re-enable foreign key checks
        if Desiru::Persistence::Database.connection.adapter_scheme == :sqlite
          Desiru::Persistence::Database.connection.run('PRAGMA foreign_keys = ON')
        end
      end
    end

    def with_clean_database
      setup_connection
      clean_tables

      # Debug: Check if clean after setup
      if ENV['DEBUG_DB']
        count = begin
          Desiru::Persistence::Database.connection[:module_executions].count
        rescue StandardError
          0
        end
        puts "\nDEBUG: After clean_tables, module_executions has #{count} records"
      end

      yield
    ensure
      clean_tables
    end
  end
end

# Configure RSpec to use database helper for persistence tests
RSpec.configure do |config|
  # Force new database connection for each spec file to ensure isolation
  config.before(:context, :persistence) do
    DatabaseHelper.setup_connection(force_new: true)
  end

  # Use around hook for each persistence test to ensure clean data
  config.around(:each, :persistence) do |example|
    DatabaseHelper.with_clean_database do
      example.run
    end
  end

  # Cleanup after each spec file
  config.after(:context, :persistence) do
    Desiru::Persistence::Database.disconnect
  rescue StandardError
    nil
  end
end
