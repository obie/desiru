# frozen_string_literal: true

require 'graphql'
require_relative 'data_loader'

module Desiru
  module GraphQL
    # Generates GraphQL schemas from Desiru signatures
    class SchemaGenerator
      attr_reader :signatures, :modules, :data_loader

      def initialize
        @signatures = {}
        @modules = {}
        @type_cache = {}
        @schema_class = nil
        @data_loader = DataLoader.new
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
        return @schema_class if @schema_class && @signatures.empty?

        query_class = build_query_type

        @schema_class = Class.new(::GraphQL::Schema) do
          query(query_class) if query_class
        end

        @schema_class
      end

      private

      def build_query_type
        return nil if @signatures.empty?

        query_fields = build_query_fields

        Class.new(::GraphQL::Schema::Object) do
          graphql_name 'Query'
          description 'Desiru query operations'

          query_fields.each do |field_name, field_def|
            # Create a resolver class for each field
            resolver_class = Class.new(::GraphQL::Schema::Resolver) do
              # Set the return type
              type field_def[:type], null: false

              # Add arguments
              field_def[:arguments].each do |arg_name, arg_def|
                argument arg_name, arg_def[:type], required: arg_def[:required]
              end

              # Define resolve method
              define_method :resolve do |**args|
                field_def[:resolver].call(args)
              end
            end

            # Add field with resolver
            field field_name, resolver: resolver_class, description: field_def[:description]
          end
        end
      end

      def build_query_fields
        fields = {}

        @signatures.each do |operation_name, signature|
          output_type = build_output_type(signature)

          arguments = {}
          signature.input_fields.each do |field_name, field|
            arguments[camelcase_field_name(field_name)] = {
              type: graphql_type_for_field(field),
              required: !field.optional
            }
          end

          fields[operation_name.to_sym] = {
            type: output_type,
            description: "Generated from signature: #{signature.raw_signature}",
            arguments: arguments,
            resolver: ->(args) { execute_signature(operation_name, signature, args) }
          }
        end

        fields
      end

      def build_mutation_type
        # Mutations could be added for signatures that modify state
        nil
      end

      def build_output_type(signature)
        type_name = "Output#{signature.object_id}"
        return @type_cache[type_name] if @type_cache[type_name]

        output_field_defs = {}
        signature.output_fields.each do |field_name, field|
          output_field_defs[camelcase_field_name(field_name)] = {
            type: graphql_type_for_field(field),
            null: field.optional,
            description: field.description
          }
        end

        output_type = Class.new(::GraphQL::Schema::Object) do
          graphql_name type_name
          description 'Generated output type'

          output_field_defs.each do |field_name, field_def|
            field field_name, field_def[:type],
                  null: field_def[:null],
                  description: field_def[:description]
          end
        end

        @type_cache[type_name] = output_type
      end

      def graphql_type_for_field(field)
        base_type = case field.type
                    when :string
                      ::GraphQL::Types::String
                    when :int, :integer
                      ::GraphQL::Types::Int
                    when :float
                      ::GraphQL::Types::Float
                    when :bool, :boolean
                      ::GraphQL::Types::Boolean
                    when :list
                      # Handle list types
                      element_type = graphql_type_for_element(field.element_type)
                      [element_type]
                    when :literal
                      # Create enum type for literal values
                      create_enum_type(field)
                    else
                      ::GraphQL::Types::String
                    end

        if field.optional
          base_type
        else
          # Arrays are already wrapped, so handle them differently
          base_type.is_a?(Array) ? [base_type.first, { null: false }] : base_type.to_non_null_type
        end
      end

      def graphql_type_for_element(element_type)
        case element_type
        when Hash
          # Handle typed arrays like List[Literal['yes', 'no']]
          if element_type[:type] == :literal
            create_enum_type_from_values(element_type[:values])
          else
            ::GraphQL::Types::String
          end
        else
          # Simple types
          case element_type
          when :string then ::GraphQL::Types::String
          when :int, :integer then ::GraphQL::Types::Int
          when :float then ::GraphQL::Types::Float
          when :bool, :boolean then ::GraphQL::Types::Boolean
          else ::GraphQL::Types::String
          end
        end
      end

      def create_enum_type(field)
        enum_name = "#{field.name.to_s.capitalize}Enum"
        return @type_cache[enum_name] if @type_cache[enum_name]

        # Extract literal values from the field's validator
        values = extract_literal_values(field)

        enum_type = Class.new(::GraphQL::Schema::Enum) do
          graphql_name enum_name
          description "Enum for #{field.name}"

          values.each do |val|
            value val.upcase.gsub(/[^A-Z0-9_]/, '_'), value: val
          end
        end

        @type_cache[enum_name] = enum_type
      end

      def create_enum_type_from_values(values)
        enum_name = "Literal#{values.map(&:capitalize).join}Enum"
        return @type_cache[enum_name] if @type_cache[enum_name]

        enum_type = Class.new(::GraphQL::Schema::Enum) do
          graphql_name enum_name

          values.each do |val|
            value val.upcase.gsub(/[^A-Z0-9_]/, '_'), value: val
          end
        end

        @type_cache[enum_name] = enum_type
      end

      def extract_literal_values(field)
        # Try to extract values from the field's validator
        if field.respond_to?(:validator) && field.validator.respond_to?(:instance_variable_get)
          field.validator.instance_variable_get(:@values) || []
        elsif field.respond_to?(:element_type) && field.element_type.is_a?(Hash)
          field.element_type[:values] || []
        else
          []
        end
      end

      def execute_signature(operation_name, signature, args)
        # Convert GraphQL arguments from camelCase to snake_case
        inputs = transform_graphql_args(args)

        # Check if we have a registered module for this operation
        if @modules[operation_name]
          # Use DataLoader for batch optimization
          loader = @data_loader.for(@modules[operation_name].class)
          promise = loader.load(inputs)

          # In a real GraphQL implementation, this would be handled by the executor
          # For now, we'll resolve immediately
          result = promise.value

          # Transform module result to GraphQL response format
          transform_module_result(result)
        else
          # Fallback: create a module instance on the fly
          module_class = infer_module_class(signature)
          module_instance = module_class.new(signature)
          result = module_instance.call(inputs)
          transform_module_result(result)
        end
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
        parts[0] + parts[1..-1].map(&:capitalize).join
      end
    end
  end
end
