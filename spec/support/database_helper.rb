# frozen_string_literal: true

require 'desiru/persistence'
require 'desiru/persistence/setup'

module DatabaseHelper
  @connection_setup = false
  @mutex = Mutex.new

  class << self
    def setup_connection
      @mutex.synchronize do
        return if @connection_setup && Desiru::Persistence::Database.connection

        # Disconnect any existing connection
        begin
          Desiru::Persistence::Database.disconnect
        rescue StandardError
          nil
        end

        # Clear repository cache
        Desiru::Persistence.instance_variable_set(:@repositories, {})

        # Reset Setup if loaded
        Desiru::Persistence::Setup.instance_variable_set(:@initialized, false) if defined?(Desiru::Persistence::Setup)

        # Connect to in-memory database
        Desiru::Persistence::Database.connect('sqlite::memory:')
        Desiru::Persistence::Database.migrate!

        @connection_setup = true
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
        %i[training_examples optimization_results module_executions api_requests].each do |table|
          begin
            if tables.include?(table)
              count = Desiru::Persistence::Database.connection[table].count
              Desiru::Persistence::Database.connection[table].delete
              puts "Cleaned #{count} records from #{table}" if ENV['DEBUG'] && count > 0
            end
          rescue Sequel::DatabaseError => e
            # Table might not exist yet, which is fine
            puts "Warning: Could not clean table #{table}: #{e.message}" if ENV['DEBUG']
          end
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
      yield
    ensure
      clean_tables
    end
  end
end

# Configure RSpec to use database helper for persistence tests
RSpec.configure do |config|
  # Setup connection once before all persistence tests
  config.before(:suite) do
    # Initialize connection for persistence tests
    DatabaseHelper.setup_connection if ENV['PERSISTENCE_TESTS']
  end

  # Use around hook for each persistence test to ensure clean data
  config.around(:each, :persistence) do |example|
    DatabaseHelper.with_clean_database do
      example.run
    end
  end

  # Cleanup after all tests
  config.after(:suite) do
    Desiru::Persistence::Database.disconnect
  rescue StandardError
    nil
  end
end
