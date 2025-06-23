# frozen_string_literal: true

module Desiru
  module Core
    class Example
      attr_reader :inputs, :labels

      def initialize(**kwargs)
        @data = kwargs
        @inputs = {}
        @labels = {}

        kwargs.each do |key, value|
          if key.to_s.end_with?('_input')
            @inputs[key.to_s.sub(/_input$/, '').to_sym] = value
          elsif key.to_s.end_with?('_output')
            @labels[key.to_s.sub(/_output$/, '').to_sym] = value
          else
            @inputs[key] = value
          end
        end
      end

      def [](key)
        @data[key]
      end

      def []=(key, value)
        @data[key] = value
        update_inputs_and_labels(key, value)
      end

      def keys
        @data.keys
      end

      def values
        @data.values
      end

      def to_h
        @data.dup
      end

      def with_inputs(**new_inputs)
        merged_data = @data.dup
        new_inputs.each do |key, value|
          input_key = key.to_s.end_with?('_input') ? key : :"#{key}_input"
          merged_data[input_key] = value
        end
        self.class.new(**merged_data)
      end

      def method_missing(method_name, *args, &)
        if @data.key?(method_name)
          @data[method_name]
        elsif method_name.to_s.end_with?('=')
          key = method_name.to_s.chop.to_sym
          self[key] = args.first
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @data.key?(method_name) || method_name.to_s.end_with?('=') || super
      end

      def ==(other)
        return false unless other.is_a?(self.class)

        @data == other.instance_variable_get(:@data)
      end

      def hash
        @data.hash
      end

      def inspect
        "#<#{self.class.name} inputs=#{@inputs.inspect} labels=#{@labels.inspect}>"
      end

      private

      def update_inputs_and_labels(key, value)
        if key.to_s.end_with?('_input')
          @inputs[key.to_s.sub(/_input$/, '').to_sym] = value
        elsif key.to_s.end_with?('_output')
          @labels[key.to_s.sub(/_output$/, '').to_sym] = value
        else
          @inputs[key] = value
        end
      end
    end
  end
end
