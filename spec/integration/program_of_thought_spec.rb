# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ProgramOfThought Module Integration' do
  let(:mock_model) do
    double('Model', complete: { content: generated_response })
  end

  let(:signature) do
    "numbers: array, operation: string -> code: string, result: string, error: string"
  end

  let(:test_inputs) do
    {
      numbers: [1, 2, 3, 4, 5],
      operation: 'sum'
    }
  end

  let(:generated_response) do
    <<~'RUBY'
      ```ruby
      def solve(**inputs)
        numbers = inputs[:numbers]
        operation = inputs[:operation]
        
        case operation
        when 'sum'
          { result: numbers.sum }
        when 'product'
          { result: numbers.reduce(:*) }
        when 'average'
          { result: numbers.sum.to_f / numbers.size }
        else
          { result: "Unknown operation: #{operation}" }
        end
      end
      ```
    RUBY
  end

  before do
    Desiru::Core.reset_traces!
  end

  describe 'Basic functionality' do
    let(:program_of_thought) do
      Desiru::Modules::ProgramOfThought.new(
        signature,
        model: mock_model,
        code_language: 'ruby',
        safe_mode: true
      )
    end

    it 'generates and executes Ruby code successfully' do
      result = program_of_thought.forward(**test_inputs)

      expect(result[:result]).to eq(15) # sum of [1,2,3,4,5]
      expect(result[:code]).to include('def solve')
      expect(result[:error]).to be_nil
    end

    it 'captures generated code in output' do
      result = program_of_thought.forward(**test_inputs)

      expect(result[:code]).to be_a(String)
      expect(result[:code]).to include('numbers.sum')
      expect(result[:code]).to include('def solve')
    end

    it 'handles different operations correctly' do
      product_inputs = test_inputs.merge(operation: 'product')
      result = program_of_thought.forward(**product_inputs)

      expect(result[:result]).to eq(120) # product of [1,2,3,4,5]
    end

    it 'generates appropriate prompts based on inputs and signature' do
      expected_prompt_parts = [
        'Given inputs:',
        'numbers: [1, 2, 3, 4, 5]',
        'operation: sum',
        'Expected outputs:',
        'ruby code',
        "method called 'solve'"
      ]

      expect(mock_model).to receive(:complete) do |args|
        prompt = args[:messages].first[:content]
        expected_prompt_parts.each do |part|
          expect(prompt.downcase).to include(part.downcase)
        end
        { content: generated_response }
      end

      program_of_thought.forward(**test_inputs)
    end
  end

  describe 'Safe mode functionality' do
    let(:dangerous_response) do
      <<~RUBY
        ```ruby
        def solve(**inputs)
          system("rm -rf /")
          { result: "Dangerous operation" }
        end
        ```
      RUBY
    end

    let(:program_of_thought_safe) do
      Desiru::Modules::ProgramOfThought.new(
        signature,
        model: double('Model', complete: { content: dangerous_response }),
        code_language: 'ruby',
        safe_mode: true
      )
    end

    it 'blocks dangerous code execution in safe mode' do
      result = program_of_thought_safe.forward(**test_inputs)

      expect(result[:error]).to include('unsafe to execute')
      expect(result[:code]).to include('system("rm -rf /")')
      expect(result[:result]).to be_nil
    end

    it 'identifies various dangerous patterns' do
      dangerous_patterns = [
        'system("ls")',
        'exec("pwd")',
        'eval("puts 1")',
        '`cat /etc/passwd`',
        'File.delete("important.txt")',
        'require "net/http"',
        'IO.popen("cat file")'
      ]

      dangerous_patterns.each do |pattern|
        dangerous_code = <<~RUBY
          ```ruby
          def solve(**inputs)
            #{pattern}
            { result: "executed" }
          end
          ```
        RUBY

        model = double('Model', complete: { content: dangerous_code })
        pot = Desiru::Modules::ProgramOfThought.new(signature, model: model, safe_mode: true)

        result = pot.forward(**test_inputs)
        expect(result[:error]).to include('unsafe to execute'), "Pattern '#{pattern}' should be blocked"
      end
    end

    let(:program_of_thought_unsafe) do
      Desiru::Modules::ProgramOfThought.new(
        signature,
        model: mock_model,
        code_language: 'ruby',
        safe_mode: false
      )
    end

    it 'allows code execution when safe mode is disabled' do
      result = program_of_thought_unsafe.forward(**test_inputs)

      expect(result[:result]).to eq(15)
      expect(result[:error]).to be_nil
    end
  end

  describe 'Error handling' do
    let(:invalid_ruby_response) do
      <<~RUBY
        ```ruby
        def solve(**inputs)
          numbers = inputs[:numbers]
          invalid syntax here
          { result: numbers.sum }
        end
        ```
      RUBY
    end

    let(:program_of_thought_error) do
      Desiru::Modules::ProgramOfThought.new(
        signature,
        model: double('Model', complete: { content: invalid_ruby_response }),
        code_language: 'ruby'
      )
    end

    it 'handles syntax errors gracefully' do
      result = program_of_thought_error.forward(**test_inputs)

      expect(result[:error]).to include('Code execution failed')
      expect(result[:code]).to include('invalid syntax')
      expect(result[:result]).to be_nil
    end

    it 'handles timeout errors' do
      infinite_loop_response = <<~RUBY
        ```ruby
        def solve(**inputs)
          while true
            # infinite loop
          end
          { result: "never reached" }
        end
        ```
      RUBY

      pot_with_timeout = Desiru::Modules::ProgramOfThought.new(
        signature,
        model: double('Model', complete: { content: infinite_loop_response }),
        timeout: 0.1 # Very short timeout
      )

      result = pot_with_timeout.forward(**test_inputs)

      expect(result[:error]).to include('timed out')
    end

    it 'handles missing solve method' do
      no_solve_response = <<~RUBY
        ```ruby
        def other_method(**inputs)
          { result: "wrong method" }
        end
        ```
      RUBY

      pot_no_solve = Desiru::Modules::ProgramOfThought.new(
        signature,
        model: double('Model', complete: { content: no_solve_response })
      )

      result = pot_no_solve.forward(**test_inputs)

      expect(result[:error]).to include("does not define a 'solve' method")
    end
  end

  describe 'Code extraction' do
    let(:program_of_thought) do
      Desiru::Modules::ProgramOfThought.new(signature, model: mock_model)
    end

    it 'extracts code from markdown blocks' do
      response_with_markdown = <<~TEXT
        Here's the solution:

        ```ruby
        def solve(**inputs)
          { result: inputs[:numbers].sum }
        end
        ```

        This code sums the numbers.
      TEXT

      model = double('Model', complete: { content: response_with_markdown })
      pot = Desiru::Modules::ProgramOfThought.new(signature, model: model)

      result = pot.forward(**test_inputs)

      expect(result[:code]).to include('def solve')
      expect(result[:code]).not_to include('Here\'s the solution')
      expect(result[:result]).to eq(15)
    end

    it 'handles code without language specification' do
      response_without_lang = <<~TEXT
        ```
        def solve(**inputs)
          { result: inputs[:numbers].sum }
        end
        ```
      TEXT

      model = double('Model', complete: { content: response_without_lang })
      pot = Desiru::Modules::ProgramOfThought.new(signature, model: model)

      result = pot.forward(**test_inputs)

      expect(result[:result]).to eq(15)
    end

    it 'handles responses without code blocks' do
      plain_code = <<~RUBY
        def solve(**inputs)
          { result: inputs[:numbers].sum }
        end
      RUBY

      model = double('Model', complete: { content: plain_code })
      pot = Desiru::Modules::ProgramOfThought.new(signature, model: model)

      result = pot.forward(**test_inputs)

      expect(result[:result]).to eq(15)
    end
  end

  describe 'Multiple programming languages' do
    it 'supports Ruby code generation' do
      pot_ruby = Desiru::Modules::ProgramOfThought.new(
        signature,
        model: mock_model,
        code_language: 'ruby'
      )

      result = pot_ruby.forward(**test_inputs)

      expect(result[:result]).to eq(15)
    end

    it 'handles Python code generation (not executed)' do
      python_response = <<~PYTHON
        ```python
        def solve(**inputs):
            numbers = inputs['numbers']
            operation = inputs['operation']
        #{'    '}
            if operation == 'sum':
                return {'result': sum(numbers)}
            else:
                return {'result': f'Unknown operation: {operation}'}
        ```
      PYTHON

      pot_python = Desiru::Modules::ProgramOfThought.new(
        signature,
        model: double('Model', complete: { content: python_response }),
        code_language: 'python'
      )

      result = pot_python.forward(**test_inputs)

      expect(result[:error]).to include('Python code execution not yet implemented')
      expect(result[:python_code]).to include('def solve')
    end

    it 'validates supported languages' do
      expect do
        Desiru::Modules::ProgramOfThought.new(
          signature,
          model: mock_model,
          code_language: 'unsupported'
        )
      end.to raise_error(Desiru::ModuleError, /Unsupported language/)
    end
  end

  describe 'Output formatting and type coercion' do
    let(:signature_with_types) do
      double('Signature',
             output_fields: {
               code: double(type: :string, default: nil, description: nil),
               count: double(type: :int, default: 0, description: nil),
               average: double(type: :float, default: 0.0, description: nil),
               valid: double(type: :bool, default: false, description: nil),
               items: double(type: :list, default: [], description: nil)
             },
             input_fields: {
               data: double(type: :array, description: nil)
             })
    end

    let(:typed_response) do
      <<~RUBY
        ```ruby
        def solve(**inputs)
          data = inputs[:data]
          {
            count: data.size.to_s,      # String that should be coerced to int
            average: "3.5",             # String that should be coerced to float
            valid: "true",              # String that should be coerced to bool
            items: data.first(3)        # Array
          }
        end
        ```
      RUBY
    end

    it 'coerces output types according to signature' do
      pot_typed = Desiru::Modules::ProgramOfThought.new(
        signature_with_types,
        model: double('Model', complete: { content: typed_response })
      )

      result = pot_typed.forward(data: [1, 2, 3, 4, 5])

      expect(result[:count]).to be_a(Integer)
      expect(result[:count]).to eq(5)
      expect(result[:average]).to be_a(Float)
      expect(result[:average]).to eq(3.5)
      expect(result[:valid]).to be(true)
      expect(result[:items]).to be_an(Array)
      expect(result[:items]).to eq([1, 2, 3])
    end

    it 'handles type coercion errors gracefully' do
      invalid_response = <<~RUBY
        ```ruby
        def solve(**inputs)
          { count: "not_a_number" }
        end
        ```
      RUBY

      pot_invalid = Desiru::Modules::ProgramOfThought.new(
        signature_with_types,
        model: double('Model', complete: { content: invalid_response })
      )

      result = pot_invalid.forward(data: [1, 2, 3])

      # Should not crash, should return the original value
      expect(result[:count]).to eq("not_a_number")
    end
  end

  describe 'Integration with trace collection' do
    let(:program_of_thought) do
      Desiru::Modules::ProgramOfThought.new(signature, model: mock_model)
    end

    it 'does not interfere with trace collection' do
      # Enable manual tracing context
      Desiru::Core.trace_context.with_trace(
        module_name: 'ProgramOfThought',
        signature: signature,
        inputs: test_inputs
      ) do
        program_of_thought.forward(**test_inputs)
      end

      expect(Desiru::Core.trace_collector.size).to eq(1)

      trace = Desiru::Core.trace_collector.traces.first
      expect(trace.module_name).to eq('ProgramOfThought')
      expect(trace.inputs).to eq(test_inputs)
      expect(trace.success?).to be(true)
    end

    it 'captures trace metadata when available' do
      # Mock the TraceContext to check metadata addition
      trace_context = double('TraceContext')
      allow(trace_context).to receive(:current).and_return(true)
      allow(trace_context).to receive(:add_metadata)

      stub_const('Desiru::TraceContext', trace_context)

      program_of_thought.forward(**test_inputs)

      expect(trace_context).to have_received(:add_metadata).with(
        hash_including(code_language: 'ruby', safe_mode: true)
      )
    end
  end

  describe 'Complex computation scenarios' do
    let(:complex_signature) do
      double('Signature',
             output_fields: {
               code: double(type: :string, default: nil, description: nil),
               fibonacci_result: double(type: :int, default: 0, description: nil),
               prime_check: double(type: :bool, default: false, description: nil),
               factors: double(type: :list, default: [], description: nil)
             },
             input_fields: {
               n: double(type: :int, description: 'Input number')
             })
    end

    let(:complex_response) do
      <<~RUBY
        ```ruby
        def solve(**inputs)
          n = inputs[:n]
        #{'  '}
          # Fibonacci
          def fibonacci(num)
            return num if num <= 1
            fibonacci(num - 1) + fibonacci(num - 2)
          end
        #{'  '}
          # Prime check
          def is_prime(num)
            return false if num < 2
            (2..Math.sqrt(num)).none? { |i| num % i == 0 }
          end
        #{'  '}
          # Factors
          def factors(num)
            (1..num).select { |i| num % i == 0 }
          end
        #{'  '}
          {
            fibonacci_result: fibonacci(n),
            prime_check: is_prime(n),
            factors: factors(n)
          }
        end
        ```
      RUBY
    end

    it 'handles complex mathematical computations' do
      pot_complex = Desiru::Modules::ProgramOfThought.new(
        complex_signature,
        model: double('Model', complete: { content: complex_response }),
        timeout: 2 # Allow more time for complex computation
      )

      result = pot_complex.forward(n: 10)

      expect(result[:fibonacci_result]).to eq(55) # 10th Fibonacci number
      expect(result[:prime_check]).to be(false)   # 10 is not prime
      expect(result[:factors]).to eq([1, 2, 5, 10]) # Factors of 10
    end

    it 'handles edge cases in complex computations' do
      pot_complex = Desiru::Modules::ProgramOfThought.new(
        complex_signature,
        model: double('Model', complete: { content: complex_response })
      )

      # Test edge case: n = 2
      result = pot_complex.forward(n: 2)

      expect(result[:fibonacci_result]).to eq(1)
      expect(result[:prime_check]).to be(true)
      expect(result[:factors]).to eq([1, 2])
    end
  end

  describe 'Error recovery and robustness' do
    it 'recovers from model errors' do
      failing_model = double('Model')
      allow(failing_model).to receive(:complete).and_raise(StandardError.new('Model failed'))

      pot_with_failing_model = Desiru::Modules::ProgramOfThought.new(
        signature,
        model: failing_model
      )

      result = pot_with_failing_model.forward(**test_inputs)

      expect(result[:error]).to include('ProgramOfThought error')
      expect(result[:code]).to eq('')
    end

    it 'handles malformed responses gracefully' do
      malformed_responses = [
        '',
        'No code here',
        '```\n# Empty code block\n```',
        '```ruby\n# No solve method\n```'
      ]

      malformed_responses.each do |response|
        model = double('Model', complete: { content: response })
        pot = Desiru::Modules::ProgramOfThought.new(signature, model: model)

        result = pot.forward(**test_inputs)

        expect(result).to have_key(:error)
        expect(result[:code]).to be_a(String)
      end
    end
  end
end
