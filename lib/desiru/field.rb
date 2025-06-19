# frozen_string_literal: true

module Desiru
  # Represents a field in a signature with type information and metadata
  class Field
    attr_reader :name, :type, :description, :optional, :default, :validator, :literal_values, :element_type,
                :original_type

    alias optional? optional

    def initialize(name, type = :string, description: nil, optional: false, default: nil, validator: nil,
                   literal_values: nil, element_type: nil, original_type: nil)
      @name = name.to_sym
      @type = normalize_type(type)
      @original_type = original_type || type.to_s
      @description = description
      @optional = optional
      @default = default
      @literal_values = literal_values&.map(&:freeze)&.freeze if literal_values
      @element_type = element_type
      @validator = validator || default_validator
    end

    def valid?(value)
      return true if optional && value.nil?
      return true if value.nil? && !default.nil?

      raise ValidationError, validation_error_message(value) unless validator.call(value)

      true
    end

    def coerce(value)
      return default if value.nil? && !default.nil?
      return value if value.nil? && optional

      case type
      when :string
        value.to_s
      when :int, :integer
        value.to_i
      when :float
        value.to_f
      when :bool, :boolean
        case value.to_s.downcase
        when 'true', 'yes', '1', 't'
          true
        when 'false', 'no', '0', 'f'
          false
        else
          !value.nil?
        end
      when :literal
        # For literal types, ensure the value is a string and matches one of the allowed values
        coerced = value.to_s
        unless literal_values.include?(coerced)
          raise ValidationError, "Value '#{coerced}' is not one of allowed values: #{literal_values.join(', ')}"
        end

        coerced
      when :list, :array
        array_value = Array(value)
        # If we have an element type, coerce each element
        if element_type && element_type[:type] == :literal
          array_value.map do |elem|
            coerced_elem = elem.to_s
            unless element_type[:literal_values].include?(coerced_elem)
              allowed = element_type[:literal_values].join(', ')
              raise ValidationError,
                    "Array element '#{coerced_elem}' is not one of allowed values: #{allowed}"
            end

            coerced_elem
          end
        else
          array_value
        end
      when :hash, :dict
        value.is_a?(Hash) ? value : {}
      else
        value
      end
    end

    def to_h
      result = {
        name: name,
        type: type,
        description: description,
        optional: optional,
        default: default
      }
      result[:literal_values] = literal_values if literal_values
      result[:element_type] = element_type if element_type
      result.compact
    end

    private

    def validation_error_message(value)
      case type
      when :string
        "#{name} must be a string, got #{value.class}"
      when :int, :integer
        "#{name} must be an integer, got #{value.class}"
      when :float
        "#{name} must be a float, got #{value.class}"
      when :bool, :boolean
        "#{name} must be a boolean (true/false), got #{value.class}"
      when :list, :array
        if element_type && element_type[:type] == :literal
          "#{name} must be an array of literal values: #{element_type[:literal_values].join(', ')}"
        else
          "#{name} must be a list, got #{value.class}"
        end
      when :literal
        "#{name} must be one of: #{literal_values.join(', ')}"
      when :hash, :dict
        "#{name} must be a hash, got #{value.class}"
      else
        "#{name} validation failed for value: #{value}"
      end
    end

    def normalize_type(type)
      # If type is already a symbol, return it
      return type if type.is_a?(Symbol)

      case type.to_s.downcase
      when 'str', 'string'
        :string
      when 'int', 'integer'
        :int
      when 'float', 'number', 'double'
        :float
      when 'bool', 'boolean'
        :bool
      when 'list', 'array'
        :list
      when 'hash', 'dict', 'dictionary'
        :hash
      when 'literal'
        :literal
      else
        type.to_sym
      end
    end

    def default_validator
      case type
      when :string
        ->(value) { value.is_a?(String) }
      when :int
        ->(value) { value.is_a?(Integer) }
      when :float
        ->(value) { value.is_a?(Float) || value.is_a?(Integer) }
      when :bool
        ->(value) { value.is_a?(TrueClass) || value.is_a?(FalseClass) }
      when :literal
        ->(value) { value.is_a?(String) && literal_values.include?(value) }
      when :list
        if element_type && element_type[:type] == :literal
          ->(value) { value.is_a?(Array) && value.all? { |elem| element_type[:literal_values].include?(elem.to_s) } }
        else
          ->(value) { value.is_a?(Array) }
        end
      when :hash
        ->(value) { value.is_a?(Hash) }
      else
        ->(_value) { true }
      end
    end
  end
end
