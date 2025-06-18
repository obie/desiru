# frozen_string_literal: true

require_relative 'persistence/database'
require_relative 'persistence/models'
require_relative 'persistence/repository'

module Desiru
  # Database persistence layer for Desiru
  module Persistence
    class << self
      attr_writer :database_url

      def database_url
        @database_url ||= ENV['DESIRU_DATABASE_URL'] || 'sqlite://desiru.db'
      end

      def connect!
        Database.connect(database_url)
      end

      def disconnect!
        Database.disconnect
      end

      def migrate!
        Database.migrate!
        Repository.setup!
      end

      def repositories
        @repositories ||= {}
      end

      def register_repository(name, repository)
        repositories[name] = repository
      end

      def [](name)
        repositories[name] || raise("Repository #{name} not found")
      end

      def enabled?
        !Database.connection.nil?
      rescue StandardError
        false
      end
    end
  end
end
