# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Desiru::Core::Example do
  describe '#initialize' do
    it 'accepts keyword arguments and stores them' do
      example = described_class.new(question: 'What is 2+2?', answer: '4')
      expect(example[:question]).to eq('What is 2+2?')
      expect(example[:answer]).to eq('4')
    end

    it 'separates inputs and labels based on _input and _output suffixes' do
      example = described_class.new(
        question_input: 'What is the capital of France?',
        answer_output: 'Paris',
        context: 'Geography question'
      )

      expect(example.inputs).to eq({
                                     question: 'What is the capital of France?',
                                     context: 'Geography question'
                                   })
      expect(example.labels).to eq({ answer: 'Paris' })
    end
  end

  describe '#[]' do
    let(:example) { described_class.new(foo: 'bar', baz: 'qux') }

    it 'retrieves values by key' do
      expect(example[:foo]).to eq('bar')
      expect(example[:baz]).to eq('qux')
    end

    it 'returns nil for non-existent keys' do
      expect(example[:missing]).to be_nil
    end
  end

  describe '#[]=' do
    let(:example) { described_class.new(foo: 'bar') }

    it 'sets values by key' do
      example[:foo] = 'new_value'
      expect(example[:foo]).to eq('new_value')
    end

    it 'updates inputs when setting a regular key' do
      example[:new_key] = 'value'
      expect(example.inputs[:new_key]).to eq('value')
    end

    it 'updates inputs when setting an _input key' do
      example[:query_input] = 'test query'
      expect(example.inputs[:query]).to eq('test query')
    end

    it 'updates labels when setting an _output key' do
      example[:result_output] = 'test result'
      expect(example.labels[:result]).to eq('test result')
    end
  end

  describe '#with_inputs' do
    let(:example) { described_class.new(question_input: 'Q1', answer_output: 'A1') }

    it 'creates a new example with additional inputs' do
      new_example = example.with_inputs(context: 'Math')

      expect(new_example).not_to equal(example)
      expect(new_example[:context_input]).to eq('Math')
      expect(new_example[:question_input]).to eq('Q1')
      expect(new_example[:answer_output]).to eq('A1')
    end

    it 'handles keys already ending with _input' do
      new_example = example.with_inputs(extra_input: 'Extra')
      expect(new_example[:extra_input]).to eq('Extra')
    end
  end

  describe '#method_missing' do
    let(:example) { described_class.new(foo: 'bar', baz: 'qux') }

    it 'allows accessing values as methods' do
      expect(example.foo).to eq('bar')
      expect(example.baz).to eq('qux')
    end

    it 'allows setting values with method= syntax' do
      example.new_attr = 'new_value'
      expect(example[:new_attr]).to eq('new_value')
    end

    it 'raises NoMethodError for undefined methods' do
      expect { example.undefined_method }.to raise_error(NoMethodError)
    end
  end

  describe '#respond_to_missing?' do
    let(:example) { described_class.new(foo: 'bar') }

    it 'returns true for existing keys' do
      expect(example.respond_to?(:foo)).to be true
    end

    it 'returns true for setter methods' do
      expect(example.respond_to?(:new_attr=)).to be true
    end

    it 'returns false for undefined methods' do
      expect(example.respond_to?(:undefined_method)).to be false
    end
  end

  describe '#==' do
    it 'returns true for examples with same data' do
      example1 = described_class.new(foo: 'bar', baz: 'qux')
      example2 = described_class.new(foo: 'bar', baz: 'qux')

      expect(example1).to eq(example2)
    end

    it 'returns false for examples with different data' do
      example1 = described_class.new(foo: 'bar')
      example2 = described_class.new(foo: 'baz')

      expect(example1).not_to eq(example2)
    end

    it 'returns false when comparing to non-Example objects' do
      example = described_class.new(foo: 'bar')
      expect(example).not_to eq({ foo: 'bar' })
    end
  end

  describe '#to_h' do
    it 'returns a hash representation of the example' do
      example = described_class.new(foo: 'bar', baz: 'qux')
      expect(example.to_h).to eq({ foo: 'bar', baz: 'qux' })
    end

    it 'returns a copy, not the original hash' do
      example = described_class.new(foo: 'bar')
      hash = example.to_h
      hash[:foo] = 'modified'

      expect(example[:foo]).to eq('bar')
    end
  end

  describe '#keys and #values' do
    let(:example) { described_class.new(a: 1, b: 2, c: 3) }

    it 'returns all keys' do
      expect(example.keys).to contain_exactly(:a, :b, :c)
    end

    it 'returns all values' do
      expect(example.values).to contain_exactly(1, 2, 3)
    end
  end

  describe '#inspect' do
    it 'provides a readable representation' do
      example = described_class.new(
        question_input: 'Q',
        answer_output: 'A',
        context: 'C'
      )

      expect(example.inspect).to include('Desiru::Core::Example')
      # Check for essential parts while being flexible about hash format
      expect(example.inspect).to include('Desiru::Core::Example')
      expect(example.inspect).to include('inputs=')
      expect(example.inspect).to include('labels=')
      
      # Verify the content is present regardless of hash format
      inspect_str = example.inspect
      expect(inspect_str).to include('"Q"')
      expect(inspect_str).to include('"C"')
      expect(inspect_str).to include('"A"')
      expect(inspect_str).to include('question')
      expect(inspect_str).to include('context')
      expect(inspect_str).to include('answer')
    end
  end
end
