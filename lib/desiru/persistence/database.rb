# frozen_string_literal: true

require 'sequel'
require 'logger'

module Desiru
  module Persistence
    # Database connection and migration management
    module Database
      class << self
        attr_reader :connection

        def connect(database_url = nil)
          url = database_url || Persistence.database_url

          @connection = Sequel.connect(
            url,
            logger: logger,
            max_connections: max_connections
          )

          # Enable foreign keys for SQLite
          @connection.run('PRAGMA foreign_keys = ON') if sqlite?

          @connection
        end

        def disconnect
          @connection&.disconnect
          @connection = nil
        end

        def migrate!
          raise 'Not connected to database' unless @connection

          Sequel.extension :migration
          migrations_path = File.expand_path('../../../db/migrations', __dir__)
          Sequel::Migrator.run(@connection, migrations_path)
          
          # Initialize persistence layer after migrations
          require_relative 'setup'
          Setup.initialize!(@connection)
        end

        def transaction(&)
          raise 'Not connected to database' unless @connection

          @connection.transaction(&)
        end

        private

        def logger
          return nil unless ENV['DESIRU_DEBUG'] || ENV['DEBUG']

          Logger.new($stdout).tap do |logger|
            logger.level = Logger::INFO
          end
        end

        def max_connections
          ENV['DESIRU_DB_MAX_CONNECTIONS']&.to_i || 10
        end

        def sqlite?
          @connection&.adapter_scheme == :sqlite
        end
      end
    end
  end
end
