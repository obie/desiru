# frozen_string_literal: true

require 'graphql'

module Desiru
  module GraphQL
    # GraphQL-compatible batch loader that integrates with GraphQL's lazy execution
    class BatchLoader < ::GraphQL::Dataloader::Source
      def initialize(module_instance)
        super()
        @module_instance = module_instance
      end

      # Fetch implementation for GraphQL::Dataloader
      def fetch(inputs_array)
        if @module_instance.respond_to?(:batch_forward)
          # Use batch processing if available
          @module_instance.batch_forward(inputs_array)
        else
          # Fall back to individual processing
          inputs_array.map { |inputs| @module_instance.call(inputs) }
        end
      end
    end

    # Module loader that provides batch loading for Desiru modules
    class ModuleLoader < ::GraphQL::Dataloader::Source
      def initialize(operation_name, modules)
        super()
        @operation_name = operation_name
        @modules = modules
      end

      def fetch(args_array)
        module_instance = @modules[@operation_name.to_s] || @modules[@operation_name.to_sym]
        
        raise "Module not found for operation: #{@operation_name}" unless module_instance
        
        # Transform GraphQL arguments to snake_case
        transformed_args = args_array.map { |args| transform_graphql_args(args) }
        
        results = if module_instance.respond_to?(:batch_forward)
          # Batch process all requests
          module_instance.batch_forward(transformed_args)
        else
          # Fall back to individual processing
          transformed_args.map { |args| module_instance.call(args) }
        end
        
        # Transform results back to camelCase
        results.map { |result| transform_module_result(result) }
      end
      
      private
      
      def transform_graphql_args(args)
        # Convert camelCase keys to snake_case
        args.transform_keys do |key|
          key_str = key.to_s
          if key_str =~ /[a-z][A-Z]/
            key_str.gsub(/([A-Z])/, '_\1').downcase.to_sym
          else
            key_str.downcase.to_sym
          end
        end
      end
      
      def transform_module_result(result)
        # Convert ModuleResult to hash with camelCase keys
        if result.respond_to?(:to_h)
          result.to_h.transform_keys { |key| camelcase_field_name(key) }
        else
          result
        end
      end
      
      def camelcase_field_name(field_name)
        # Convert snake_case to camelCase
        clean_name = field_name.to_s.gsub('?', '')
        parts = clean_name.split('_')
        parts[0] + parts[1..-1].map(&:capitalize).join
      end
    end
  end
end