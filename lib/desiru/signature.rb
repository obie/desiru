# frozen_string_literal: true

module Desiru
  # Represents input/output specifications for modules
  # Supports DSL-style signature strings like "question -> answer"
  class Signature
    # FieldWrapper provides a test-compatible interface for Field objects
    class FieldWrapper
      def initialize(field)
        @field = field
      end

      def type
        @field.type
      end

      def description
        @field.description
      end

      def optional
        @field.optional
      end

      def optional?
        @field.optional?
      end

      def name
        @field.name
      end

      def method_missing(method, *, &)
        @field.send(method, *, &)
      end

      def respond_to_missing?(method, include_private = false)
        @field.respond_to?(method, include_private)
      end
    end

    # FieldHash allows access by both string and symbol keys
    class FieldHash < Hash
      def [](key)
        field = super(key.to_sym)
        field ? FieldWrapper.new(field) : nil
      end

      def []=(key, value)
        super(key.to_sym, value)
      end

      def keys
        super.map(&:to_s)
      end

      def key?(key)
        super(key.to_sym)
      end

      alias include? key?
      alias has_key? key?
    end

    attr_reader :raw_signature

    def input_fields
      @input_fields_wrapper
    end

    def output_fields
      @output_fields_wrapper
    end

    # Aliases for test compatibility
    alias inputs input_fields
    alias outputs output_fields

    def self.wrap(signature_string_or_instance)
      case signature_string_or_instance
      when Signature
        signature_string_or_instance
      when String
        Signature.new(signature_string_or_instance)
      else
        raise ModuleError, 'Signature must be a String or Signature instance'
      end
    end

    def initialize(signature_string, descriptions: {})
      @raw_signature = signature_string
      @descriptions = descriptions
      @input_fields = {}
      @output_fields = {}
      @input_fields_wrapper = FieldHash.new
      @output_fields_wrapper = FieldHash.new

      parse_signature!
    end

    def valid_inputs?(inputs)
      missing = required_input_fields - inputs.keys.map(&:to_sym)
      raise SignatureError, "Missing required inputs: #{missing.join(', ')}" if missing.any?

      inputs.each do |name, value|
        field = @input_fields[name.to_sym]
        next unless field

        # Field.validate will raise ValidationError if validation fails
        field.valid?(value)
      end

      true
    end

    def valid_outputs?(outputs)
      missing = required_output_fields - outputs.keys.map(&:to_sym)
      raise ValidationError, "Missing required outputs: #{missing.join(', ')}" if missing.any?

      outputs.each do |name, value|
        field = @output_fields[name.to_sym]
        next unless field

        # Field.validate will raise ValidationError if validation fails
        field.valid?(value)
      end

      true
    end

    def coerce_inputs(inputs)
      result = {}

      @input_fields.each do |name, field|
        value = inputs[name] || inputs[name.to_s]
        result[name] = field.coerce(value)
      end

      result
    end

    def coerce_outputs(outputs)
      result = {}

      @output_fields.each do |name, field|
        value = outputs[name] || outputs[name.to_s]
        result[name] = field.coerce(value)
      end

      result
    end

    def to_h
      {
        signature: raw_signature,
        inputs: @input_fields.transform_values(&:to_h),
        outputs: @output_fields.transform_values(&:to_h)
      }
    end

    def to_s
      raw_signature
    end

    private

    def parse_signature!
      parts = raw_signature.split('->').map(&:strip)
      raise ArgumentError, "Invalid signature format: #{raw_signature}" unless parts.size == 2

      parse_fields(parts[0], @input_fields)
      parse_fields(parts[1], @output_fields)
    end

    def parse_fields(fields_string, target_hash)
      return if fields_string.empty?

      # Split fields properly, handling commas inside brackets
      fields = []
      current_field = String.new
      bracket_count = 0

      fields_string.chars.each do |char|
        if char == '['
          bracket_count += 1
        elsif char == ']'
          bracket_count -= 1
        elsif char == ',' && bracket_count.zero?
          fields << current_field.strip
          current_field = String.new
          next
        end
        current_field << char
      end
      fields << current_field.strip unless current_field.empty?

      fields.each do |field_str|
        # Parse field with type annotation
        if field_str.include?(':')
          name, type_info = field_str.split(':', 2).map(&:strip)
          # Check for optional marker on field name or type
          optional = name.end_with?('?') || type_info.include?('?')
          # Clean field name by removing trailing ?
          name = name.gsub(/\?$/, '')

          # Extract description if present (in quotes at the end)
          description = nil
          # Look for description only after the type definition, not within brackets
          if type_info =~ /^([^"]+?)\s+"([^"]+)"$/
            type_info = ::Regexp.last_match(1).strip
            description = ::Regexp.last_match(2)
          end

          # Remove optional marker before parsing type
          clean_type_info = type_info.gsub('?', '').strip
          type_data = parse_type(clean_type_info)
          # Store the original type string for tests
          type_data[:original_type] = clean_type_info
        else
          name = field_str
          # Check if field name ends with ?
          optional = name.end_with?('?')
          name = name.gsub(/\?$/, '')
          type_data = { type: :string, original_type: 'string' }
          description = nil
        end

        # Use extracted description or fallback to descriptions hash
        description ||= @descriptions[name.to_sym] || @descriptions[name.to_s]

        # Create field with parsed type data
        field_args = {
          description: description,
          optional: optional,
          original_type: type_data[:original_type]
        }

        # Add literal values if present
        field_args[:literal_values] = type_data[:literal_values] if type_data[:literal_values]

        # Add element type for typed arrays
        field_args[:element_type] = type_data[:element_type] if type_data[:element_type]

        field = Field.new(
          name,
          type_data[:type],
          **field_args
        )

        target_hash[name.to_sym] = field

        # Also add to wrapper for dual access
        if target_hash == @input_fields
          @input_fields_wrapper[name.to_sym] = field
        elsif target_hash == @output_fields
          @output_fields_wrapper[name.to_sym] = field
        end
      end
    end

    def parse_type(type_string)
      # Handle Literal types - need to match balanced brackets
      if type_string.start_with?('Literal[')
        # Find the matching closing bracket
        bracket_count = 0
        end_index = 0

        type_string.chars.each_with_index do |char, index|
          if char == '['
            bracket_count += 1
          elsif char == ']'
            bracket_count -= 1
            if bracket_count.zero?
              end_index = index
              break
            end
          end
        end

        if end_index.positive?
          literal_content = type_string[8...end_index] # Extract content between 'Literal[' and ']'
          values = parse_literal_values(literal_content)
          return { type: :literal, literal_values: values, original_type: type_string }
        end
      end

      # Handle List/Array types with element types
      if type_string.start_with?('List[', 'Array[')
        # Find the matching closing bracket
        bracket_count = 0
        end_index = 0
        start_index = type_string.index('[')

        type_string.chars.each_with_index do |char, index|
          next if index < start_index

          if char == '['
            bracket_count += 1
          elsif char == ']'
            bracket_count -= 1
            if bracket_count.zero?
              end_index = index
              break
            end
          end
        end

        if end_index.positive?
          element_type_str = type_string[(start_index + 1)...end_index]
          element_type_data = parse_type(element_type_str) # Recursive for nested types
          return { type: :list, element_type: element_type_data, original_type: type_string }
        end
      end

      # Handle Union types (for future implementation)
      if type_string.start_with?('Union[')
        # Placeholder for union type parsing
        return { type: :union, union_types: [], original_type: type_string } # To be implemented
      end

      # Handle basic types
      # First check if it's a list/array with simple element type (e.g., list[str])
      if type_string.downcase.start_with?('list[', 'array[')
        # Even if we couldn't parse the brackets properly above, it's still a list
        return { type: :list, original_type: type_string }
      end

      # Handle dict/dictionary types with special parsing
      return { type: :hash, original_type: type_string } if type_string.downcase.start_with?('dict[', 'dictionary[')

      clean_type = type_string.gsub(/[?\[\]]/, '').downcase
      type_sym = case clean_type
                 when 'str', 'string' then :string
                 when 'int', 'integer' then :int
                 when 'float', 'number', 'double' then :float
                 when 'bool', 'boolean' then :bool
                 when 'list', 'array' then :list
                 when 'hash', 'dict', 'dictionary' then :hash
                 else clean_type.to_sym
                 end

      { type: type_sym, original_type: type_string }
    end

    def parse_literal_values(literal_content)
      # Parse comma-separated values, handling quoted strings
      values = []
      current_value = String.new
      in_quotes = false
      quote_char = nil

      literal_content.each_char.with_index do |char, index|
        if !in_quotes && ['"', "'"].include?(char)
          in_quotes = true
          quote_char = char
          current_value << char # Include the quote in the value
        elsif in_quotes && char == quote_char
          # Check if it's escaped
          if index.positive? && literal_content[index - 1] != '\\'
            in_quotes = false
            current_value << char # Include the closing quote
            quote_char = nil
          else
            current_value << char
          end
        elsif !in_quotes && char == ','
          val = current_value.strip
          # Remove outer quotes if present
          if (val.start_with?('"') && val.end_with?('"')) || (val.start_with?("'") && val.end_with?("'"))
            val = val[1...-1]
          end
          values << val
          current_value = String.new
        else
          current_value << char
        end
      end

      # Add the last value
      unless current_value.empty?
        val = current_value.strip
        # Remove outer quotes if present
        if (val.start_with?('"') && val.end_with?('"')) || (val.start_with?("'") && val.end_with?("'"))
          val = val[1...-1]
        end
        values << val
      end

      values
    end

    def required_input_fields
      @input_fields.reject { |_, field| field.optional }.keys
    end

    def required_output_fields
      @output_fields.reject { |_, field| field.optional }.keys
    end
  end
end
