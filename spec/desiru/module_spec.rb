# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Desiru::Module do
  let(:model) { double('model') }
  let(:signature) { Desiru::Signature.new('question -> answer') }
  let(:test_module_class) do
    Class.new(described_class) do
      def forward(**inputs)
        { answer: "Test answer for: #{inputs[:question]}" }
      end
    end
  end
  let(:test_module) { test_module_class.new(signature, model: model) }

  describe '#initialize' do
    it 'creates module with signature and model' do
      expect(test_module.signature).to eq(signature)
      expect(test_module.model).to eq(model)
    end

    it 'uses default model if not provided' do
      allow(Desiru.configuration).to receive(:default_model).and_return(model)
      module_without_model = test_module_class.new(signature)
      expect(module_without_model.model).to eq(model)
    end

    it 'raises error if no model available' do
      allow(Desiru.configuration).to receive(:default_model).and_return(nil)
      expect { test_module_class.new(signature) }
        .to raise_error(ArgumentError, /No model provided/)
    end

    it 'initializes empty demos array' do
      expect(test_module.demos).to eq([])
    end
  end

  describe '#call' do
    it 'validates inputs before processing' do
      expect(signature).to receive(:validate_inputs).with({ question: 'What is DSPy?' })
      allow(signature).to receive(:coerce_inputs).and_return(question: 'What is DSPy?')
      allow(signature).to receive(:validate_outputs)
      allow(signature).to receive(:coerce_outputs).and_return(answer: 'Test answer')

      test_module.call(question: 'What is DSPy?')
    end

    it 'coerces inputs before processing' do
      allow(signature).to receive(:validate_inputs)
      expect(signature).to receive(:coerce_inputs).with({ question: 123 }).and_return(question: '123')
      allow(signature).to receive(:validate_outputs)
      allow(signature).to receive(:coerce_outputs).and_return(answer: 'Test answer')

      test_module.call(question: 123)
    end

    it 'calls forward method with coerced inputs' do
      allow(signature).to receive(:validate_inputs)
      allow(signature).to receive(:coerce_inputs).and_return(question: 'What is DSPy?')
      allow(signature).to receive(:validate_outputs)
      allow(signature).to receive(:coerce_outputs).and_return(answer: 'DSPy is a framework')

      expect(test_module).to receive(:forward).with({ question: 'What is DSPy?' }).and_call_original
      test_module.call(question: 'What is DSPy?')
    end

    it 'validates outputs after processing' do
      allow(signature).to receive(:validate_inputs)
      allow(signature).to receive(:coerce_inputs).and_return(question: 'What is DSPy?')
      expect(signature).to receive(:validate_outputs).with({ answer: 'Test answer for: What is DSPy?' })
      allow(signature).to receive(:coerce_outputs).and_return(answer: 'Test answer')

      test_module.call(question: 'What is DSPy?')
    end

    it 'returns ModuleResult with outputs' do
      allow(signature).to receive(:validate_inputs)
      allow(signature).to receive(:coerce_inputs).and_return(question: 'What is DSPy?')
      allow(signature).to receive(:validate_outputs)
      allow(signature).to receive(:coerce_outputs).and_return(answer: 'DSPy is a framework')

      result = test_module.call(question: 'What is DSPy?')
      expect(result).to be_a(Desiru::ModuleResult)
      expect(result.answer).to eq('DSPy is a framework')
    end

    it 'implements retry logic on failure' do
      allow(signature).to receive(:validate_inputs)
      allow(signature).to receive(:coerce_inputs).and_return(question: 'What is DSPy?')
      allow(signature).to receive(:validate_outputs)
      allow(signature).to receive(:coerce_outputs).and_return(answer: 'Test answer')

      call_count = 0
      allow(test_module).to receive(:forward) do
        call_count += 1
        raise StandardError, 'Temporary failure' if call_count < 3

        { answer: 'Success after retries' }
      end

      result = test_module.call(question: 'What is DSPy?')
      expect(call_count).to eq(3)
      expect(result.answer).to eq('Test answer')
    end

    it 'raises error after max retries' do
      allow(signature).to receive(:validate_inputs)
      allow(signature).to receive(:coerce_inputs).and_return(question: 'What is DSPy?')

      allow(test_module).to receive(:forward).and_raise(StandardError, 'Persistent failure')

      expect { test_module.call(question: 'What is DSPy?') }
        .to raise_error(Desiru::ModuleError, 'Module execution failed: Persistent failure')
    end
  end

  describe '#with_demos' do
    it 'adds demonstrations to the module' do
      demos = [
        { question: 'What is Ruby?', answer: 'A programming language' },
        { question: 'What is Rails?', answer: 'A web framework' }
      ]

      new_module = test_module.with_demos(demos)
      expect(new_module.demos).to eq(demos)
      expect(new_module).not_to eq(test_module) # Returns new instance
    end
  end

  describe '#forward' do
    it 'raises NotImplementedError in base class' do
      base_module = described_class.new(signature, model: model)
      expect { base_module.forward(question: 'test') }
        .to raise_error(NotImplementedError, /Subclasses must implement/)
    end
  end
end

RSpec.describe Desiru::ModuleResult do
  describe '#initialize' do
    it 'creates result with given outputs' do
      result = described_class.new(answer: 'DSPy is a framework', confidence: 0.95)
      expect(result.outputs).to eq(answer: 'DSPy is a framework', confidence: 0.95)
    end
  end

  describe 'dynamic accessors' do
    let(:result) { described_class.new(answer: 'DSPy is a framework', confidence: 0.95) }

    it 'provides getter methods for outputs' do
      expect(result.answer).to eq('DSPy is a framework')
      expect(result.confidence).to eq(0.95)
    end

    it 'provides predicate methods for boolean outputs' do
      result = described_class.new(success: true, valid: false)
      expect(result.success?).to be true
      expect(result.valid?).to be false
    end

    it 'raises NoMethodError for undefined outputs' do
      expect { result.undefined_field }.to raise_error(NoMethodError)
    end
  end

  describe '#to_h' do
    it 'returns outputs hash' do
      result = described_class.new(answer: 'DSPy is a framework', confidence: 0.95)
      expect(result.to_h).to eq(answer: 'DSPy is a framework', confidence: 0.95)
    end
  end

  describe '#[]' do
    it 'accesses outputs by key' do
      result = described_class.new(answer: 'DSPy is a framework', confidence: 0.95)
      expect(result[:answer]).to eq('DSPy is a framework')
      expect(result['confidence']).to eq(0.95)
    end
  end
end
