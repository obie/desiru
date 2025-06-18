# frozen_string_literal: true

require 'graphql'
require_relative 'data_loader'
require_relative 'batch_loader'
require_relative 'type_builder'

module Desiru
  module GraphQL
    # Generates GraphQL schemas from Desiru signatures
    class SchemaGenerator
      attr_reader :signatures, :modules, :data_loader

      def initialize
        @signatures = {}
        @modules = {}
        @type_cache = {} # Instance cache for schema-specific types
        @schema_class = nil
        @data_loader = DataLoader.new
      end

      # Clear the global type cache (useful for testing or reloading)
      def self.clear_type_cache!
        TypeBuilder.clear_type_cache!
      end

      # Register a signature with a name for GraphQL query/mutation
      def register_signature(name, signature)
        @signatures[name] = signature
      end

      # Register a module instance to handle a specific operation
      def register_module(name, module_instance)
        @modules[name] = module_instance
        # Auto-register signature if module has one
        @signatures[name] ||= module_instance.signature if module_instance.respond_to?(:signature)
      end

      # Register multiple modules at once
      def register_modules(modules_hash)
        modules_hash.each { |name, mod| register_module(name, mod) }
      end

      # Generate a GraphQL schema from registered signatures
      def generate_schema
        # Always rebuild if signatures have changed
        return @schema_class if @schema_class && @last_signature_count == @signatures.size

        @last_signature_count = @signatures.size
        query_class = build_query_type

        @schema_class = Class.new(::GraphQL::Schema) do
          query(query_class) if query_class

          # Enable GraphQL's built-in dataloader
          use ::GraphQL::Dataloader

          # Enable lazy execution for batch loading
          lazy_resolve(::GraphQL::Execution::Lazy, :value)
        end

        @schema_class
      end

      private

      def build_query_type
        return nil if @signatures.empty?

        query_fields = build_query_fields
        query_class_builder = self

        Class.new(::GraphQL::Schema::Object) do
          graphql_name 'Query'
          description 'Desiru query operations'

          query_fields.each do |field_name, field_def|
            query_class_builder.add_query_field(self, field_name, field_def)
          end
        end
      end

      def add_query_field(query_class, field_name, field_def)
        # Add field directly without resolver class
        query_class.field field_name, field_def[:type],
                          null: false,
                          description: field_def[:description] do
          # Add arguments
          field_def[:arguments].each do |arg_name, arg_def|
            argument arg_name, arg_def[:type], required: arg_def[:required]
          end
        end

        # Define the resolver method for this field
        query_class.define_method field_name do |**args|
          if field_def[:module_instance].respond_to?(:batch_forward)
            # Get the dataloader for this request
            dataloader = context.dataloader
            # Load through the dataloader
            dataloader.with(
              Desiru::GraphQL::ModuleLoader,
              field_name,
              field_def[:modules]
            ).load(args)
          else
            # Direct execution
            field_def[:resolver].call(args, context)
          end
        end
      end

      def build_query_fields
        fields = {}

        @signatures.each do |operation_name, signature|
          output_type = TypeBuilder.build_output_type(signature)

          arguments = {}
          signature.input_fields.each do |field_name, field|
            arguments[camelcase_field_name(field_name)] = {
              type: TypeBuilder.graphql_type_for_field(field),
              required: !field.optional
            }
          end

          fields[operation_name.to_sym] = {
            type: output_type,
            description: "Generated from signature: #{signature.raw_signature}",
            arguments: arguments,
            resolver: ->(args, context) { execute_signature(operation_name, signature, args, context) },
            module_instance: @modules[operation_name],
            modules: @modules
          }
        end

        fields
      end

      def build_mutation_type
        # Mutations could be added for signatures that modify state
        nil
      end

      def execute_signature(operation_name, signature, args, context = {})
        # Convert GraphQL arguments from camelCase to snake_case
        inputs = transform_graphql_args(args)

        # Get data loader from context if available
        context[:data_loader] || @data_loader

        # Check if we have a registered module for this operation
        if @modules[operation_name]
          module_instance = @modules[operation_name]

          # Direct execution - batching will be handled by the executor
        else
          # Fallback: create a module instance on the fly
          module_class = infer_module_class(signature)
          module_instance = module_class.new(signature)
        end
        result = module_instance.call(inputs)
        transform_module_result(result)
      end

      def transform_graphql_args(args)
        # Convert camelCase keys to snake_case, but handle single-word keys correctly
        args.transform_keys do |key|
          key_str = key.to_s
          # Only convert if there's actually a capital letter after the first character
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

      def infer_module_class(signature)
        # Infer the appropriate module class based on signature characteristics
        if signature.raw_signature.include?('reasoning')
          Desiru::Modules::ChainOfThought
        else
          Desiru::Modules::Predict
        end
      end

      def camelcase_field_name(field_name)
        # Convert snake_case to camelCase for GraphQL conventions
        # Remove trailing '?' for optional fields
        clean_name = field_name.to_s.gsub('?', '')
        parts = clean_name.split('_')
        parts[0] + parts[1..].map(&:capitalize).join
      end
    end
  end
end
