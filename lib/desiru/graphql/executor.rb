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

      # Execute with automatic lazy loading support
      def execute_with_lazy_loading(query_string, variables: {}, context: {}, operation_name: nil)
        context[:data_loader] = @data_loader

        # Use GraphQL's built-in lazy execution
        @schema.execute(
          query_string,
          variables: variables,
          context: context,
          operation_name: operation_name
        ) do |schema_query|
          # Configure lazy loading behavior
          schema_query.after_lazy_resolve do |value|
            # Trigger batch loading after each lazy resolution
            @data_loader.perform_loads
            value
          end
        end
      end

      private

      def batch_execute
        # Start batch loading context
        @data_loader.clear! if @data_loader.respond_to?(:clear!)

        # Execute the GraphQL queries with lazy loading support
        result = yield

        # Always perform loads at least once to ensure batch processing
        @data_loader.perform_loads

        # Then perform any additional pending loads
        @data_loader.perform_loads while pending_loads?

        result
      end

      def pending_loads?
        pending_loads = @data_loader.instance_variable_get(:@pending_loads)
        pending_loads&.any? { |_, batch| !batch.empty? }
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
            # Create a lazy resolver that integrates with DataLoader
            ::GraphQL::Execution::Lazy.new do
              data_loader = context[:data_loader]

              # Ensure batch loads are performed before accessing value
              data_loader.perform_loads if data_loader && !result.fulfilled?

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
