# frozen_string_literal: true

require 'graphql'

module Desiru
  module GraphQL
    # Custom GraphQL executor with batch loading support
    class Executor
      attr_reader :schema, :data_loader

      def initialize(schema, data_loader: nil)
        @schema = schema
        @data_loader = data_loader || DataLoader.new
      end

      # Execute a GraphQL query with batch loading
      def execute(query_string, variables: {}, context: {}, operation_name: nil)
        # Add data loader to context
        context[:data_loader] = @data_loader

        # Wrap execution with batch loading
        result = nil
        batch_execute do
          result = @schema.execute(
            query_string,
            variables: variables,
            context: context,
            operation_name: operation_name
          )
        end

        result
      end

      # Execute multiple queries in a single batch
      def execute_batch(queries)
        results = []

        batch_execute do
          queries.each do |query_params|
            query_params[:context] ||= {}
            query_params[:context][:data_loader] = @data_loader

            results << @schema.execute(
              query_params[:query],
              variables: query_params[:variables] || {},
              context: query_params[:context],
              operation_name: query_params[:operation_name]
            )
          end
        end

        results
      end

      private

      def batch_execute
        # Start batch loading context
        @data_loader.clear! if @data_loader.respond_to?(:clear!)

        # Execute the GraphQL queries
        result = yield

        # Perform all pending batch loads
        @data_loader.perform_loads if @data_loader.respond_to?(:perform_loads)

        result
      end
    end

    # GraphQL field extension for lazy loading
    class LazyFieldExtension < ::GraphQL::Schema::FieldExtension
      def resolve(object:, arguments:, context:)
        result = yield(object, arguments)

        # If result is a promise, handle it appropriately
        if result.respond_to?(:then) && result.respond_to?(:fulfilled?)
          if result.fulfilled?
            result.value
          else
            # Create a lazy resolver
            ::GraphQL::Execution::Lazy.new do
              result.value
            end
          end
        else
          result
        end
      end
    end

    # Middleware for automatic batch loading
    class BatchLoaderMiddleware
      def initialize(app)
        @app = app
      end

      def call(env)
        # Extract GraphQL context
        context = env['graphql.context'] || {}

        # Ensure data loader is available
        context[:data_loader] ||= DataLoader.new
        env['graphql.context'] = context

        # Execute with batch loading
        @app.call(env)
      ensure
        # Clean up after request
        context[:data_loader]&.clear!
      end
    end
  end
end
