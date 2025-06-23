# frozen_string_literal: true

module Desiru
  module Modules
    # Basic prediction module - the fundamental building block
    class Predict < Module
      DEFAULT_SIGNATURE = 'question: string -> answer: string'

      def initialize(signature = nil, model: nil, **)
        signature ||= DEFAULT_SIGNATURE
        super
      end

      def forward(inputs)
        prompt = build_prompt(inputs)

        response = model.complete(
          prompt,
          temperature: config[:temperature],
          max_tokens: config[:max_tokens],
          demos: demos
        )

        Desiru.logger.info("Predict response: #{response}")

        parse_response(response[:content])
      end

      protected

      def build_prompt(inputs)
        {
          system: build_system_prompt,
          user: build_user_prompt(inputs)
        }
      end

      def build_system_prompt
        <<~PROMPT
          You are a helpful AI assistant. You will be given inputs and must produce outputs according to the following specification:

          #{format_signature}

          Format your response with each output field on its own line using the pattern:
          field_name: value

          For example, if the output field is "answer", write:
          answer: Your answer here

          #{format_descriptions}
        PROMPT
      end

      def build_user_prompt(inputs)
        lines = ['Given the following inputs:']

        inputs.each do |key, value|
          lines << "#{key}: #{format_value(value)}"
        end

        lines << "\nProvide the following outputs:"
        signature.output_fields.each_key do |key|
          lines << "#{key}:"
        end

        lines.join("\n")
      end

      def format_signature
        "#{format_fields(signature.input_fields)} -> #{format_fields(signature.output_fields)}"
      end

      def format_fields(fields)
        fields.map do |name, field|
          type_str = field.type == :string ? '' : ": #{field.type}"
          "#{name}#{type_str}"
        end.join(', ')
      end

      def format_descriptions
        descriptions = []

        all_fields = signature.input_fields.merge(signature.output_fields)
        all_fields.each do |name, field|
          next unless field.description

          descriptions << "- #{name}: #{field.description}"
        end

        return '' if descriptions.empty?

        "\nField descriptions:\n#{descriptions.join("\n")}"
      end

      def format_value(value)
        case value
        when Array
          value.map(&:to_s).join(', ')
        when Hash
          value.to_json
        else
          value.to_s
        end
      end

      def parse_response(content)
        # Simple parser - looks for key: value patterns
        result = {}

        signature.output_fields.each_key do |field_name|
          # Look for the field name followed by a colon
          pattern = /#{Regexp.escape(field_name.to_s)}:\s*(.+?)(?=\n\w+:|$)/mi
          match = content.match(pattern)

          if match
            value = match[1].strip
            result[field_name] = parse_field_value(field_name, value)
          end
        end

        result
      end

      def parse_field_value(field_name, value_str)
        field = signature.output_fields[field_name]
        return value_str unless field

        case field.type
        when :int
          value_str.to_i
        when :float
          value_str.to_f
        when :bool
          %w[true yes 1].include?(value_str.downcase)
        when :list
          # Simple list parsing - comma separated
          value_str.split(',').map(&:strip)
        when :hash
          # Try to parse as JSON
          begin
            JSON.parse(value_str)
          rescue StandardError
            value_str
          end
        else
          value_str
        end
      end
    end
  end
end

# Register in the main module namespace for convenience
module Desiru
  Predict = Modules::Predict
end
