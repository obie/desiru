# frozen_string_literal: true

module Desiru
  module GraphQL
    # Utility for warming the GraphQL type cache with common types
    module TypeCacheWarmer
      extend self

      # Pre-generate commonly used types to improve cold-start performance
      def warm_common_types!
        warm_common_output_types!
        warm_common_enums!
      end

      # Get statistics about the type cache
      def cache_stats
        cache = TypeBuilder.instance_variable_get(:@type_cache)
        mutex = TypeBuilder.instance_variable_get(:@cache_mutex)

        mutex.synchronize do
          {
            total_types: cache.size,
            output_types: cache.keys.count { |k| k.start_with?('Output:') },
            enum_types: cache.keys.count { |k| k.include?('Enum') },
            cache_keys: cache.keys
          }
        end
      end

      private

      def warm_common_output_types!
        common_field_sets.each do |fields|
          signature = create_mock_signature(fields)
          TypeBuilder.build_output_type(signature)
        end
      end

      def common_field_sets
        [
          # Single field types
          { id: create_field(:string, false) },
          { result: create_field(:string, true) },
          { output: create_field(:string, true) },
          { message: create_field(:string, true) },
          {
            id: create_field(:string, false),
            result: create_field(:string, true),
            timestamp: create_field(:float, true)
          },
          {
            output: create_field(:string, true),
            confidence: create_field(:float, true),
            reasoning: create_field(:string, true)
          },
          {
            success: create_field(:bool, false),
            message: create_field(:string, true),
            data: create_field(:string, true)
          }
        ]
      end

      def create_field(type, optional)
        Struct.new(:type, :optional, :description).new(type, optional, nil)
      end

      def create_mock_signature(fields)
        Struct.new(:output_fields).new(fields)
      end

      def warm_common_enums!
        # Common enum value sets
        common_enum_values = [
          %w[pending processing completed failed],
          %w[low medium high critical],
          %w[yes no maybe],
          %w[active inactive suspended],
          %w[draft published archived]
        ]

        cache = TypeBuilder.instance_variable_get(:@type_cache)
        mutex = TypeBuilder.instance_variable_get(:@cache_mutex)

        common_enum_values.each do |values|
          EnumBuilder.create_enum_from_values(values, cache, mutex)
        end
      end
    end
  end
end
