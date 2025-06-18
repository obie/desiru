# frozen_string_literal: true

require 'graphql'
require_relative 'enum_builder'

module Desiru
  module GraphQL
    # Handles GraphQL type generation and caching
    module TypeBuilder
      extend self

      @type_cache = {}
      @cache_mutex = Mutex.new

      class << self
        attr_accessor :type_cache, :cache_mutex
      end

      def clear_type_cache!
        @cache_mutex.synchronize do
          @type_cache.clear
        end
      end

      def build_output_type(signature)
        # Create a stable cache key based on signature structure
        cache_key = generate_type_cache_key('Output', signature.output_fields)

        # Check cache first
        @cache_mutex.synchronize do
          return @type_cache[cache_key] if @type_cache[cache_key]
        end

        output_field_defs = build_field_definitions(signature.output_fields)

        output_type = Class.new(::GraphQL::Schema::Object) do
          graphql_name "Output#{cache_key.hash.abs}"
          description 'Generated output type'

          output_field_defs.each do |field_name, field_def|
            field field_name, field_def[:type],
                  null: field_def[:null],
                  description: field_def[:description]
          end
        end

        # Store in cache
        @cache_mutex.synchronize do
          @type_cache[cache_key] = output_type
        end

        output_type
      end

      def graphql_type_for_field(field)
        case field.type
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
          EnumBuilder.create_enum_type(field, @type_cache, @cache_mutex)
        else
          ::GraphQL::Types::String
        end
      end


      private

      def build_field_definitions(fields)
        field_defs = {}
        fields.each do |field_name, field|
          field_defs[camelcase_field_name(field_name)] = {
            type: graphql_type_for_field(field),
            null: field.optional,
            description: field.description
          }
        end
        field_defs
      end

      def graphql_type_for_element(element_type)
        case element_type
        when Hash
          # Handle typed arrays like List[Literal['yes', 'no']]
          if element_type[:type] == :literal
            EnumBuilder.create_enum_from_values(element_type[:values], @type_cache, @cache_mutex)
          else
            ::GraphQL::Types::String
          end
        else
          # Simple types
          element_to_graphql_type(element_type)
        end
      end

      def element_to_graphql_type(element_type)
        case element_type
        when :int, :integer then ::GraphQL::Types::Int
        when :float then ::GraphQL::Types::Float
        when :bool, :boolean then ::GraphQL::Types::Boolean
        else ::GraphQL::Types::String
        end
      end


      def camelcase_field_name(field_name)
        # Convert snake_case to camelCase for GraphQL conventions
        # Remove trailing '?' for optional fields
        clean_name = field_name.to_s.gsub('?', '')
        parts = clean_name.split('_')
        parts[0] + parts[1..].map(&:capitalize).join
      end

      def generate_type_cache_key(prefix, fields)
        # Generate a stable cache key based on field structure
        field_signatures = fields.map do |name, field|
          "#{name}:#{field.type}:#{field.optional}:#{field.element_type if field.respond_to?(:element_type)}"
        end.sort

        "#{prefix}:#{field_signatures.join('|')}"
      end
    end
  end
end
