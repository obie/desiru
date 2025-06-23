# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Desiru::Core::Prediction do
  let(:example) { Desiru::Core::Example.new(question: 'What is 2+2?', context: 'Math') }

  describe '#initialize' do
    it 'creates an empty prediction with no arguments' do
      prediction = described_class.new
      expect(prediction.completions).to eq({})
      expect(prediction.example).to be_a(Desiru::Core::Example)
    end

    it 'accepts an example' do
      prediction = described_class.new(example)
      expect(prediction.example).to eq(example)
    end

    it 'accepts completions as keyword arguments' do
      prediction = described_class.new(example, answer: '4', reasoning: 'Basic arithmetic')
      expect(prediction.completions).to eq({ answer: '4', reasoning: 'Basic arithmetic' })
    end

    it 'accepts completions hash directly' do
      prediction = described_class.new(example, completions: { answer: '4' })
      expect(prediction.completions).to eq({ answer: '4' })
    end

    it 'accepts metadata' do
      prediction = described_class.new(example, answer: '4', metadata: { confidence: 0.9 })
      expect(prediction.metadata).to eq({ confidence: 0.9 })
    end
  end

  describe '#[]' do
    let(:prediction) { described_class.new(example, answer: '4') }

    it 'returns completion values first' do
      expect(prediction[:answer]).to eq('4')
    end

    it 'falls back to example values' do
      expect(prediction[:question]).to eq('What is 2+2?')
      expect(prediction[:context]).to eq('Math')
    end

    it 'returns nil for non-existent keys' do
      expect(prediction[:missing]).to be_nil
    end
  end

  describe '#[]=' do
    let(:prediction) { described_class.new(example) }

    it 'sets completion values' do
      prediction[:answer] = '4'
      expect(prediction[:answer]).to eq('4')
      expect(prediction.completions[:answer]).to eq('4')
    end
  end

  describe '#get' do
    let(:prediction) { described_class.new(example, answer: '4') }

    it 'returns completion values' do
      expect(prediction.get(:answer)).to eq('4')
    end

    it 'returns example values as fallback' do
      expect(prediction.get(:question)).to eq('What is 2+2?')
    end

    it 'returns default value when key not found' do
      expect(prediction.get(:missing, 'default')).to eq('default')
    end
  end

  describe '#keys and #values' do
    let(:prediction) { described_class.new(example, answer: '4') }

    it 'returns combined unique keys from completions and example' do
      expect(prediction.keys).to contain_exactly(:answer, :question, :context)
    end

    it 'returns values in order of keys' do
      keys = prediction.keys
      values = prediction.values

      keys.each_with_index do |key, i|
        expect(prediction[key]).to eq(values[i])
      end
    end
  end

  describe '#to_h' do
    let(:prediction) { described_class.new(example, answer: '4') }

    it 'merges example and completion data' do
      expect(prediction.to_h).to eq({
                                      question: 'What is 2+2?',
                                      context: 'Math',
                                      answer: '4'
                                    })
    end

    it 'completions override example values' do
      prediction[:question] = 'Modified question'
      expect(prediction.to_h[:question]).to eq('Modified question')
    end
  end

  describe '#to_example' do
    let(:prediction) { described_class.new(example, answer: '4') }

    it 'creates an Example with merged data' do
      new_example = prediction.to_example

      expect(new_example).to be_a(Desiru::Core::Example)
      expect(new_example[:question]).to eq('What is 2+2?')
      expect(new_example[:context]).to eq('Math')
      expect(new_example[:answer]).to eq('4')
    end
  end

  describe '#metadata' do
    let(:prediction) do
      described_class.new(example, answer: '4', metadata: { confidence: 0.9, model: 'gpt-4' })
    end

    it 'returns a copy of metadata' do
      metadata = prediction.metadata
      expect(metadata).to eq({ confidence: 0.9, model: 'gpt-4' })

      metadata[:modified] = true
      expect(prediction.metadata).not_to have_key(:modified)
    end
  end

  describe '#set_metadata' do
    let(:prediction) { described_class.new(example) }

    it 'sets metadata values' do
      prediction.set_metadata(:confidence, 0.95)
      expect(prediction.metadata[:confidence]).to eq(0.95)
    end
  end

  describe '#method_missing' do
    let(:prediction) { described_class.new(example, answer: '4') }

    it 'allows setting completions with method= syntax' do
      prediction.reasoning = 'Simple addition'
      expect(prediction[:reasoning]).to eq('Simple addition')
    end

    it 'returns completion values as methods' do
      expect(prediction.answer).to eq('4')
    end

    it 'delegates to example for example methods' do
      expect(prediction.question).to eq('What is 2+2?')
    end

    it 'raises NoMethodError for undefined methods' do
      expect { prediction.undefined_method }.to raise_error(NoMethodError)
    end
  end

  describe '#respond_to_missing?' do
    let(:prediction) { described_class.new(example, answer: '4') }

    it 'returns true for setter methods' do
      expect(prediction.respond_to?(:new_attr=)).to be true
    end

    it 'returns true for completion keys' do
      expect(prediction.respond_to?(:answer)).to be true
    end

    it 'returns true for example methods' do
      expect(prediction.respond_to?(:question)).to be true
    end

    it 'returns false for undefined methods' do
      expect(prediction.respond_to?(:undefined_method)).to be false
    end
  end

  describe '#==' do
    let(:example1) { Desiru::Core::Example.new(question: 'Q1') }
    let(:example2) { Desiru::Core::Example.new(question: 'Q2') }

    it 'returns true for predictions with same data' do
      pred1 = described_class.new(example1, answer: 'A1', metadata: { confidence: 0.9 })
      pred2 = described_class.new(example1, answer: 'A1', metadata: { confidence: 0.9 })

      expect(pred1).to eq(pred2)
    end

    it 'returns false for different completions' do
      pred1 = described_class.new(example1, answer: 'A1')
      pred2 = described_class.new(example1, answer: 'A2')

      expect(pred1).not_to eq(pred2)
    end

    it 'returns false for different examples' do
      pred1 = described_class.new(example1, answer: 'A1')
      pred2 = described_class.new(example2, answer: 'A1')

      expect(pred1).not_to eq(pred2)
    end

    it 'returns false for different metadata' do
      pred1 = described_class.new(example1, answer: 'A1', metadata: { confidence: 0.9 })
      pred2 = described_class.new(example1, answer: 'A1', metadata: { confidence: 0.8 })

      expect(pred1).not_to eq(pred2)
    end

    it 'returns false when comparing to non-Prediction objects' do
      prediction = described_class.new(example1, answer: 'A1')
      expect(prediction).not_to eq({ answer: 'A1' })
    end
  end

  describe '#inspect' do
    it 'provides a readable representation' do
      prediction = described_class.new(example, answer: '4', metadata: { confidence: 0.9 })

      expect(prediction.inspect).to include('Desiru::Core::Prediction')
      # Check for essential parts while being flexible about hash format
      expect(prediction.inspect).to include('completions=')
      expect(prediction.inspect).to include('"4"')
      expect(prediction.inspect).to include('answer')
      expect(prediction.inspect).to include('example=#<Desiru::Core::Example')
      expect(prediction.inspect).to include('metadata=')
      expect(prediction.inspect).to include('confidence')
      expect(prediction.inspect).to include('0.9')
    end
  end
end
