# frozen_string_literal: true

require 'graphql'

module Desiru
  module GraphQL
    # Handles GraphQL enum type generation
    module EnumBuilder
      extend self

      def create_enum_type(field, type_cache, cache_mutex)
        values = extract_literal_values(field)
        cache_key = "Enum:#{field.name}:#{values.sort.join(',')}"

        cache_mutex.synchronize do
          return type_cache[cache_key] if type_cache[cache_key]
        end

        enum_name = "#{field.name.to_s.capitalize}Enum#{cache_key.hash.abs}"

        enum_type = Class.new(::GraphQL::Schema::Enum) do
          graphql_name enum_name
          description "Enum for #{field.name}"

          values.each do |val|
            value val.upcase.gsub(/[^A-Z0-9_]/, '_'), value: val
          end
        end

        cache_mutex.synchronize do
          type_cache[cache_key] = enum_type
        end

        enum_type
      end

      def create_enum_from_values(values, type_cache, cache_mutex)
        cache_key = "LiteralEnum:#{values.sort.join(',')}"

        cache_mutex.synchronize do
          return type_cache[cache_key] if type_cache[cache_key]
        end

        enum_name = "Literal#{cache_key.hash.abs}Enum"

        enum_type = Class.new(::GraphQL::Schema::Enum) do
          graphql_name enum_name

          values.each do |val|
            value val.upcase.gsub(/[^A-Z0-9_]/, '_'), value: val
          end
        end

        cache_mutex.synchronize do
          type_cache[cache_key] = enum_type
        end

        enum_type
      end

      private

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
    end
  end
end
