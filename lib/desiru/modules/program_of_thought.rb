# frozen_string_literal: true

require 'timeout'

module Desiru
  module Modules
    # ProgramOfThought module that generates executable code to solve problems
    # Similar to ChainOfThought but produces code instead of reasoning steps
    # Supports both Ruby and Python code generation
    class ProgramOfThought < Desiru::Module
      DEFAULT_SIGNATURE = 'question: string -> answer: string, code: string'

      def initialize(signature = nil, model: nil, **kwargs)
        # Extract our specific options before passing to parent
        @max_iterations = kwargs.delete(:max_iterations) || 1
        @code_language = validate_language(kwargs.delete(:code_language) || 'ruby')
        @timeout = kwargs.delete(:timeout) || 5 # seconds
        @safe_mode = kwargs.delete(:safe_mode) != false # default true

        # Use default signature if none provided
        signature ||= DEFAULT_SIGNATURE

        # If signature is a double/mock (for testing), store it directly
        if signature.respond_to?(:output_fields) && signature.respond_to?(:input_fields) &&
           !signature.is_a?(Signature) && !signature.is_a?(String)
          @signature = signature
          @model = model || Desiru.configuration.default_model
          @config = default_config.merge(kwargs[:config] || {})
          @demos = kwargs[:demos] || []
          @metadata = kwargs[:metadata] || {}
          @call_count = 0
          validate_model! if respond_to?(:validate_model!, true)
          register_module if respond_to?(:register_module, true)
        else
          # Pass remaining kwargs to parent (config, demos, metadata)
          super
        end
      end

      def forward(**inputs)
        trace_metadata = { code_language: @code_language, safe_mode: @safe_mode }

        if defined?(Desiru::TraceContext) && Desiru::TraceContext.respond_to?(:current) && Desiru::TraceContext.current
          Desiru::TraceContext.add_metadata(trace_metadata)
        elsif defined?(Desiru::Core) && Desiru::Core.respond_to?(:trace_context) &&
              Desiru::Core.trace_context.respond_to?(:current) && Desiru::Core.trace_context.current
          Desiru::Core.trace_context.add_metadata(trace_metadata)
        end

        # Enhance the prompt to request code generation
        code_prompt = build_code_prompt(inputs)

        # Get the model to generate code
        response = model.complete(
          messages: [{ role: 'user', content: code_prompt }],
          temperature: 0.3 # Lower temperature for more deterministic code
        )

        generated_code = extract_code(response[:content])

        Desiru.logger.debug("Generated #{@code_language} code: #{generated_code}")

        # Execute the generated code if safe
        result = if @safe_mode && !safe_to_execute?(generated_code)
                   { error: "Generated code deemed unsafe to execute" }
                 else
                   execute_code(generated_code, inputs)
                 end

        # Format outputs according to signature
        format_outputs(result, generated_code)
      rescue StandardError => e
        Desiru.logger.error("ProgramOfThought error: #{e.message}")
        format_error_output(e, '')
      end

      private

      def validate_language(language)
        supported = %w[ruby python]
        unless supported.include?(language.to_s.downcase)
          raise ModuleError, "Unsupported language: #{language}. Supported: #{supported.join(', ')}"
        end

        language.to_s.downcase
      end

      def build_code_prompt(inputs)
        prompt = "You are a programming assistant. Generate #{@code_language} code to solve this problem.\n\n"

        # Add input context
        prompt += "Given inputs:\n" if inputs.any?
        if inputs.any?
          inputs.each do |key, value|
            prompt += "#{key}: #{format_input_value(value)}\n"
          end
          prompt += "\n"
        end

        # Add expected output format
        prompt += "Expected outputs:\n"
        signature.output_fields.each do |name, field|
          next if name == :code # Skip the code field itself

          prompt += "- #{name} (#{field.type}): #{field.description || 'No description'}\n"
        end

        prompt += "\nGenerate executable #{@code_language} code that processes the inputs "
        prompt += "and returns the expected outputs. "
        prompt += "Wrap your code in triple backticks with the language identifier.\n"

        if @code_language == 'ruby'
          prompt += "The code should define a method called 'solve' that takes the inputs "
          prompt += "as keyword arguments and returns a hash with the output values."
        else # python
          prompt += "The code should define a function called 'solve' that takes the inputs "
          prompt += "as keyword arguments and returns a dictionary with the output values."
        end

        prompt
      end

      def format_input_value(value)
        case value
        when Array
          "[#{value.map { |v| format_input_value(v) }.join(', ')}]"
        when Hash
          value.to_json
        else
          value.to_s
        end
      end

      def extract_code(response)
        # Extract code from markdown code blocks
        code_match = response.match(/```#{@code_language}?\n(.*?)```/m)
        return code_match[1].strip if code_match

        # Fallback: try to extract any code block
        code_match = response.match(/```\n(.*?)```/m)
        return code_match[1].strip if code_match

        # Last resort: assume the entire response is code
        response.strip
      end

      def safe_to_execute?(code)
        return true unless @safe_mode

        # Language-specific dangerous patterns
        dangerous_patterns = case @code_language
                             when 'ruby'
                               ruby_dangerous_patterns
                             when 'python'
                               python_dangerous_patterns
                             else
                               []
                             end

        dangerous_patterns.none? { |pattern| code.match?(pattern) }
      end

      def ruby_dangerous_patterns
        [
          /system\s*\(/,
          /exec\s*\(/,
          /eval\s*\(/,
          /%x\{/,
          /`.*`/,
          /File\s*\.\s*delete/,
          /FileUtils\s*\.\s*rm/,
          /Dir\s*\.\s*delete/,
          /require\s+['"]net/,
          /Socket/,
          /Process\s*\.\s*kill/,
          /IO\s*\.\s*popen/,
          /Open3/,
          /\$SAFE\s*=/
        ]
      end

      def python_dangerous_patterns
        [
          /os\.system/,
          /subprocess/,
          /eval\s*\(/,
          /exec\s*\(/,
          /compile\s*\(/,
          /__import__/,
          /open\s*\([^,)]*,\s*['"][wa]/,
          /os\.remove/,
          /shutil\.rmtree/,
          /socket/,
          /requests/,
          /urllib/
        ]
      end

      def execute_code(code, inputs)
        case @code_language
        when 'ruby'
          execute_ruby_code(code, inputs)
        when 'python'
          execute_python_code(code, inputs)
        else
          { error: "Unsupported language for execution: #{@code_language}" }
        end
      end

      def execute_ruby_code(code, inputs)
        # Create a safe execution context
        context = Object.new

        # Use timeout for safety
        result = Timeout.timeout(@timeout) do
          # Define the code in the context
          context.instance_eval(code)

          # Call the solve method if it exists
          if context.respond_to?(:solve)
            context.solve(**inputs.transform_keys(&:to_sym))
          else
            { error: "Generated code does not define a 'solve' method" }
          end
        end

        # Ensure result is a hash
        result.is_a?(Hash) ? result : { result: result }
      rescue Timeout::Error
        { error: "Code execution timed out after #{@timeout} seconds" }
      rescue StandardError => e
        { error: "Code execution failed: #{e.message}" }
      end

      def execute_python_code(code, _inputs)
        # For Python execution, we would need to use a Python interpreter
        # This is a placeholder that returns a message about Python support
        {
          error: "Python code execution not yet implemented. Generated code saved.",
          python_code: code,
          note: "To execute Python code, integrate with a Python runtime or use system calls in non-safe mode."
        }
      end

      def format_outputs(result, generated_code)
        outputs = {}

        # Always include the generated code if requested in signature
        outputs[:code] = generated_code if signature.output_fields.key?(:code)

        if result[:error]
          # Handle error case - always include error
          outputs[:error] = result[:error]

          # Add any additional error info
          outputs[:python_code] = result[:python_code] if result[:python_code]
          outputs[:note] = result[:note] if result[:note]

          # Fill other fields with defaults
          signature.output_fields.each do |name, field|
            next if outputs.key?(name)

            outputs[name] = field.default || nil
          end
        else
          # Map result to expected outputs
          signature.output_fields.each do |name, field|
            next if name == :code # Already handled

            # Don't use || here because it will treat false as falsy
            value = result.key?(name) ? result[name] : result[name.to_s]
            outputs[name] = if value.nil?
                              field.default || nil
                            else
                              coerce_output_value(value, field)
                            end
          end
        end

        outputs
      end

      def format_error_output(error, code = '')
        outputs = {}

        # Always include code field if it's in the signature, even if empty
        outputs[:code] = code if signature.output_fields.key?(:code)
        outputs[:error] = "ProgramOfThought error: #{error.message}"

        # Fill other fields with defaults
        signature.output_fields.each do |name, field|
          next if outputs.key?(name)

          outputs[name] = field.default || nil
        end

        outputs
      end

      def coerce_output_value(value, field)
        return value unless value && field.type

        case field.type
        when :int
          # Only coerce if it's a valid integer representation
          return value unless value.to_s.match?(/\A-?\d+\z/)

          value.to_i
        when :float
          # Only coerce if it's a valid float representation
          begin
            Float(value.to_s)
          rescue StandardError
            (value)
          end
        when :bool
          return true if value.to_s.downcase == 'true'
          return false if value.to_s.downcase == 'false'

          !!value
        when :list
          Array(value)
        when :hash
          value.is_a?(Hash) ? value : { value: value }
        else
          value
        end
      rescue StandardError
        value
      end
    end
  end
end

# Register in the main module namespace for convenience
module Desiru
  ProgramOfThought = Modules::ProgramOfThought
end
