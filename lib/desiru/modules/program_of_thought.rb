# frozen_string_literal: true

module Desiru
  module Modules
    # ProgramOfThought module that generates executable code to solve problems
    # Similar to ChainOfThought but produces code instead of reasoning steps
    class ProgramOfThought < Desiru::Module
      def initialize(signature = nil, model: nil, **kwargs)
        super
        @max_iterations = kwargs[:max_iterations] || 1
        @code_language = kwargs[:code_language] || 'ruby'
      end

      def forward(**inputs)
        # Enhance the prompt to request code generation
        code_prompt = build_code_prompt(inputs)

        # Get the model to generate code
        response = model.complete(
          messages: [{ role: 'user', content: code_prompt }],
          temperature: 0.3 # Lower temperature for more deterministic code
        )

        generated_code = extract_code(response[:content])

        # Execute the generated code if safe
        result = if safe_to_execute?(generated_code)
                   execute_code(generated_code, inputs)
                 else
                   { error: "Generated code deemed unsafe to execute", code: generated_code }
                 end

        # Format outputs according to signature
        format_outputs(result, generated_code)
      end

      private

      def build_code_prompt(inputs)
        prompt = "You are a programming assistant. Generate #{@code_language} code to solve this problem.\n\n"

        # Add input context
        prompt += "Given inputs:\n"
        inputs.each do |key, value|
          prompt += "#{key}: #{value}\n"
        end

        # Add expected output format
        prompt += "\nExpected outputs:\n"
        signature.output_fields.each do |name, field|
          prompt += "- #{name} (#{field.type}): #{field.description || 'No description'}\n"
        end

        prompt += "\nGenerate executable #{@code_language} code that processes the inputs "
        prompt += "and returns the expected outputs. "
        prompt += "Wrap your code in triple backticks with the language identifier.\n"
        prompt += "The code should define a method called 'solve' that takes the inputs "
        prompt += "as keyword arguments and returns a hash with the output values."

        prompt
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
        # Basic safety checks - in production, use proper sandboxing
        dangerous_patterns = [
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
          /Process\s*\.\s*kill/
        ]

        dangerous_patterns.none? { |pattern| code.match?(pattern) }
      end

      def execute_code(code, inputs)
        # Create a safe execution context
        context = Object.new

        # Define the code in the context
        context.instance_eval(code)

        # Call the solve method if it exists
        if context.respond_to?(:solve)
          context.solve(**inputs.transform_keys(&:to_sym))
        else
          { error: "Generated code does not define a 'solve' method" }
        end
      rescue StandardError => e
        { error: "Code execution failed: #{e.message}" }
      end

      def format_outputs(result, generated_code)
        outputs = {}

        # Always include the generated code
        outputs[:code] = generated_code if signature.output_fields.key?(:code)

        if result[:error]
          # Handle error case
          outputs[:error] = result[:error]
          signature.output_fields.each do |name, field|
            next if %i[code error].include?(name)

            outputs[name] = field.default || nil
          end
        else
          # Map result to expected outputs
          signature.output_fields.each do |name, field|
            next if name == :code

            outputs[name] = result[name] || field.default || nil
          end
        end

        outputs
      end
    end
  end
end
