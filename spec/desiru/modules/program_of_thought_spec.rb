# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe Desiru::Modules::ProgramOfThought do
  let(:model) { double('model') }
  let(:signature) { Desiru::Signature.new('problem: string -> solution: string, code: string') }
  let(:module_instance) { described_class.new(signature, model: model) }

  describe '#initialize' do
    it 'sets default values' do
      expect(module_instance.instance_variable_get(:@max_iterations)).to eq(1)
      expect(module_instance.instance_variable_get(:@code_language)).to eq('ruby')
    end

    it 'accepts custom configuration' do
      custom_module = described_class.new(
        signature,
        model: model,
        max_iterations: 3,
        code_language: 'python'
      )
      expect(custom_module.instance_variable_get(:@max_iterations)).to eq(3)
      expect(custom_module.instance_variable_get(:@code_language)).to eq('python')
    end
  end

  describe '#forward' do
    let(:inputs) { { problem: 'Calculate the sum of 5 and 3' } }

    context 'with successful Ruby code generation' do
      let(:generated_code) do
        <<~RUBY
          def solve(problem:)
            # Extract numbers from the problem
            numbers = problem.scan(/\\d+/).map(&:to_i)
            sum = numbers.sum
            { solution: "The sum is \#{sum}" }
          end
        RUBY
      end

      let(:model_response) do
        {
          content: "```ruby\n#{generated_code}```",
          metadata: { model: 'test-model' }
        }
      end

      before do
        allow(model).to receive(:complete).and_return(model_response)
      end

      it 'generates and executes code successfully' do
        result = module_instance.forward(**inputs)

        expect(result[:code]).to eq(generated_code.strip)
        expect(result[:solution]).to eq('The sum is 8')
      end

      it 'calls model with appropriate prompt' do
        expect(model).to receive(:complete) do |args|
          messages = args[:messages]
          expect(messages).to be_an(Array)
          expect(messages.first[:role]).to eq('user')
          expect(messages.first[:content]).to include('problem: Calculate the sum of 5 and 3')
          expect(messages.first[:content]).to include('ruby code')
          expect(args[:temperature]).to eq(0.3)
        end.and_return(model_response)

        module_instance.forward(**inputs)
      end
    end

    context 'with Python code generation' do
      let(:python_module) do
        described_class.new(
          signature,
          model: model,
          code_language: 'python'
        )
      end

      let(:python_code) do
        <<~PYTHON
          def solve(problem):
              import re
              numbers = [int(n) for n in re.findall(r'\\d+', problem)]
              total = sum(numbers)
              return {'solution': f'The sum is {total}'}
        PYTHON
      end

      let(:model_response) do
        {
          content: "```python\n#{python_code}```",
          metadata: { model: 'test-model' }
        }
      end

      before do
        allow(model).to receive(:complete).and_return(model_response)
      end

      it 'generates Python code when specified' do
        result = python_module.forward(**inputs)

        expect(result[:code]).to eq(python_code.strip)
        # NOTE: Actual Python execution would require a Python interpreter
        # For now, we're testing the code generation part
      end
    end

    context 'with unsafe code' do
      let(:unsafe_code) do
        <<~RUBY
          def solve(problem:)
            system("rm -rf /")
            { solution: "Done" }
          end
        RUBY
      end

      let(:model_response) do
        {
          content: "```ruby\n#{unsafe_code}```",
          metadata: { model: 'test-model' }
        }
      end

      before do
        allow(model).to receive(:complete).and_return(model_response)
      end

      it 'refuses to execute unsafe code' do
        result = module_instance.forward(**inputs)

        expect(result[:code]).to eq(unsafe_code.strip)
        expect(result[:error]).to eq('Generated code deemed unsafe to execute')
      end
    end

    context 'with code execution errors' do
      let(:buggy_code) do
        <<~RUBY
          def solve(problem:)
            raise "Intentional error"
          end
        RUBY
      end

      let(:model_response) do
        {
          content: "```ruby\n#{buggy_code}```",
          metadata: { model: 'test-model' }
        }
      end

      before do
        allow(model).to receive(:complete).and_return(model_response)
      end

      it 'handles execution errors gracefully' do
        result = module_instance.forward(**inputs)

        expect(result[:code]).to eq(buggy_code.strip)
        expect(result[:error]).to include('Code execution failed')
        expect(result[:error]).to include('Intentional error')
      end
    end

    context 'with missing solve method' do
      let(:invalid_code) do
        <<~RUBY
          def calculate(x, y)
            x + y
          end
        RUBY
      end

      let(:model_response) do
        {
          content: "```ruby\n#{invalid_code}```",
          metadata: { model: 'test-model' }
        }
      end

      before do
        allow(model).to receive(:complete).and_return(model_response)
      end

      it 'handles missing solve method' do
        result = module_instance.forward(**inputs)

        expect(result[:code]).to eq(invalid_code.strip)
        expect(result[:error]).to eq("Generated code does not define a 'solve' method")
      end
    end

    context 'with complex signature' do
      let(:complex_signature) do
        Desiru::Signature.new('numbers: list[int], operation: string -> result: float, explanation: string, code: string')
      end
      let(:complex_module) { described_class.new(complex_signature, model: model) }
      let(:complex_inputs) { { numbers: [10, 20, 30], operation: 'average' } }

      let(:complex_code) do
        <<~RUBY
          def solve(numbers:, operation:)
            case operation
            when 'average'
              result = numbers.sum.to_f / numbers.length
              explanation = "The average of \#{numbers.join(', ')} is \#{result}"
            else
              result = 0.0
              explanation = "Unknown operation"
            end
            { result: result, explanation: explanation }
          end
        RUBY
      end

      let(:model_response) do
        {
          content: "```ruby\n#{complex_code}```",
          metadata: { model: 'test-model' }
        }
      end

      before do
        allow(model).to receive(:complete).and_return(model_response)
      end

      it 'handles complex inputs and outputs' do
        result = complex_module.forward(**complex_inputs)

        expect(result[:code]).to eq(complex_code.strip)
        expect(result[:result]).to eq(20.0)
        expect(result[:explanation]).to eq('The average of 10, 20, 30 is 20.0')
      end
    end
  end

  describe '#extract_code' do
    it 'extracts code from markdown code blocks' do
      response = "Here's the code:\n```ruby\ndef hello\n  'world'\nend\n```"
      code = module_instance.send(:extract_code, response)
      expect(code).to eq("def hello\n  'world'\nend")
    end

    it 'extracts code without language identifier' do
      response = "```\ndef hello\n  'world'\nend\n```"
      code = module_instance.send(:extract_code, response)
      expect(code).to eq("def hello\n  'world'\nend")
    end

    it 'returns entire response if no code blocks found' do
      response = "def hello\n  'world'\nend"
      code = module_instance.send(:extract_code, response)
      expect(code).to eq(response)
    end
  end

  describe '#safe_to_execute?' do
    it 'detects system calls' do
      unsafe_patterns = [
        'system("ls")',
        'exec("rm file")',
        'eval("code")',
        '%x{ls}',
        '`ls -la`',
        'File.delete("test")',
        'FileUtils.rm("test")',
        'Dir.delete("test")',
        'require "net/http"',
        'Socket.new',
        'Process.kill(9, pid)'
      ]

      unsafe_patterns.each do |pattern|
        expect(module_instance.send(:safe_to_execute?, pattern)).to be_falsey,
                                                                    "Expected #{pattern} to be detected as unsafe"
      end
    end

    it 'allows safe code' do
      safe_code = <<~RUBY
        def solve(x:, y:)
          result = x + y
          { sum: result }
        end
      RUBY

      expect(module_instance.send(:safe_to_execute?, safe_code)).to be_truthy
    end
  end

  describe 'integration with Desiru infrastructure' do
    it 'works with demos' do
      module_with_demos = described_class.new(
        signature,
        model: model,
        demos: [
          { problem: 'Add 2 and 3', solution: 'The sum is 5' }
        ]
      )

      expect(module_with_demos.demos).not_to be_empty
    end

    it 'supports async execution' do
      expect(described_class.ancestors).to include(Desiru::AsyncCapable)
    end

    it 'integrates with trace collection' do
      allow(model).to receive(:complete).and_return(
        content: "```ruby\ndef solve(problem:)\n  { solution: 'test' }\nend\n```",
        metadata: {}
      )

      collector = Desiru::Core::TraceCollector.new

      expect do
        Desiru::Core::TraceContext.with_collector(collector) do
          module_instance.forward(problem: 'test')
        end
      end.not_to raise_error
    end
  end
end
