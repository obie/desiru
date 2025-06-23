# frozen_string_literal: true

module Desiru
  module Core
    class Prediction
      attr_reader :completions, :example

      def initialize(example = nil, **kwargs)
        @example = example || Example.new
        @completions = {}
        @metadata = {}

        kwargs.each do |key, value|
          if key == :completions
            @completions = value
          elsif key == :metadata
            @metadata = value
          else
            @completions[key] = value
          end
        end
      end

      def [](key)
        if @completions.key?(key)
          @completions[key]
        elsif @example
          # First check the raw data in the example
          if @example[key]
            @example[key]
          else
            # Then check the inputs and labels
            @example.inputs[key] || @example.labels[key]
          end
        end
      end

      def []=(key, value)
        @completions[key] = value
      end

      def get(key, default = nil)
        @completions.fetch(key) { @example[key] || default }
      end

      def keys
        (@completions.keys + (@example&.keys || [])).uniq
      end

      def values
        keys.map { |k| self[k] }
      end

      def to_h
        result = @example&.to_h || {}
        result.merge(@completions)
      end

      def to_example
        Example.new(**to_h)
      end

      def metadata
        @metadata.dup
      end

      def set_metadata(key, value)
        @metadata[key] = value
      end

      def method_missing(method_name, *args, &)
        if method_name.to_s.end_with?('=')
          key = method_name.to_s.chop.to_sym
          self[key] = args.first
        elsif @completions.key?(method_name)
          @completions[method_name]
        elsif @example&.respond_to?(method_name)
          @example.send(method_name, *args, &)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        method_name.to_s.end_with?('=') ||
          @completions.key?(method_name) ||
          @example&.respond_to?(method_name) ||
          super
      end

      def ==(other)
        return false unless other.is_a?(self.class)

        @completions == other.completions &&
          @example == other.example &&
          @metadata == other.instance_variable_get(:@metadata)
      end

      def inspect
        "#<#{self.class.name} completions=#{@completions.inspect} example=#{@example.inspect} metadata=#{@metadata.inspect}>"
      end

      # Class method to create a Prediction from an Example
      def self.from_example(example)
        new(example)
      end
    end
  end
end
