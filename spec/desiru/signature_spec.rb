# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Desiru::Signature do
  describe '#initialize' do
    it 'parses simple signature' do
      sig = described_class.new('question -> answer')
      expect(sig.inputs.keys).to eq(['question'])
      expect(sig.outputs.keys).to eq(['answer'])
    end

    it 'parses signature with types' do
      sig = described_class.new('question: string -> answer: string')
      expect(sig.inputs['question'].type).to eq(:string)
      expect(sig.outputs['answer'].type).to eq(:string)
    end

    it 'parses signature with multiple inputs' do
      sig = described_class.new('context, question -> answer')
      expect(sig.inputs.keys).to eq(%w[context question])
    end

    it 'parses signature with multiple outputs' do
      sig = described_class.new('text -> summary, keywords')
      expect(sig.outputs.keys).to eq(%w[summary keywords])
    end

    it 'parses complex signature with types' do
      sig = described_class.new('document: string, max_length: int -> summary: string, keywords: list[str]')
      expect(sig.inputs['document'].type).to eq(:string)
      expect(sig.inputs['max_length'].type).to eq(:int)
      expect(sig.outputs['summary'].type).to eq(:string)
      expect(sig.outputs['keywords'].type).to eq(:list)
    end

    it 'accepts descriptions for fields' do
      descriptions = {
        'question' => 'The question to answer',
        'answer' => 'The generated answer'
      }
      sig = described_class.new('question -> answer', descriptions: descriptions)
      expect(sig.inputs['question'].description).to eq('The question to answer')
      expect(sig.outputs['answer'].description).to eq('The generated answer')
    end

    context 'with Literal types' do
      it 'parses single Literal type' do
        sig = described_class.new("sentiment: Literal['positive', 'negative', 'neutral'] -> score: float")
        field = sig.inputs[:sentiment]
        expect(field.type).to eq(:literal)
        expect(field.literal_values).to eq(%w[positive negative neutral])
      end

      it 'parses Literal type with double quotes' do
        sig = described_class.new('sentiment: Literal["happy", "sad"] -> result: string')
        field = sig.inputs[:sentiment]
        expect(field.type).to eq(:literal)
        expect(field.literal_values).to eq(%w[happy sad])
      end

      it 'parses Literal type without quotes' do
        sig = described_class.new('priority: Literal[high, medium, low] -> action: string')
        field = sig.inputs[:priority]
        expect(field.type).to eq(:literal)
        expect(field.literal_values).to eq(%w[high medium low])
      end

      it 'parses multiple Literal fields' do
        sig = described_class.new("status: Literal['active', 'inactive'], priority: Literal['high', 'low'] -> result: string")
        expect(sig.inputs[:status].literal_values).to eq(%w[active inactive])
        expect(sig.inputs[:priority].literal_values).to eq(%w[high low])
      end

      it 'parses nested Literal in List' do
        sig = described_class.new("responses: List[Literal['yes', 'no']] -> summary: string")
        field = sig.inputs[:responses]
        expect(field.type).to eq(:list)
        expect(field.element_type[:type]).to eq(:literal)
        expect(field.element_type[:literal_values]).to eq(%w[yes no])
      end
    end

    context 'with typed arrays' do
      it 'parses List with element type' do
        sig = described_class.new('items: List[str] -> count: int')
        field = sig.inputs[:items]
        expect(field.type).to eq(:list)
        expect(field.element_type[:type]).to eq(:string)
      end

      it 'parses Array with element type' do
        sig = described_class.new('numbers: Array[Integer] -> sum: int')
        field = sig.inputs[:numbers]
        expect(field.type).to eq(:list)
        expect(field.element_type[:type]).to eq(:int)
      end
    end

    it 'raises error for invalid signature format' do
      expect { described_class.new('invalid signature') }.to raise_error(ArgumentError, /Invalid signature format/)
    end
  end

  describe '#validate_inputs' do
    let(:signature) { described_class.new('question: string, count: int -> answer') }

    it 'validates correct inputs' do
      expect { signature.validate_inputs(question: 'What is DSPy?', count: 5) }.not_to raise_error
    end

    it 'raises error for missing required inputs' do
      expect { signature.validate_inputs(question: 'What is DSPy?') }
        .to raise_error(Desiru::SignatureError, /Missing required inputs: count/)
    end

    it 'raises error for wrong input types' do
      expect { signature.validate_inputs(question: 'What is DSPy?', count: 'five') }
        .to raise_error(Desiru::ValidationError, /count must be an integer/)
    end

    it 'ignores extra inputs' do
      expect { signature.validate_inputs(question: 'What is DSPy?', count: 5, extra: 'ignored') }
        .not_to raise_error
    end

    context 'with Literal types' do
      let(:literal_sig) { described_class.new("sentiment: Literal['positive', 'negative', 'neutral'] -> score: float") }

      it 'validates correct literal value' do
        expect { literal_sig.validate_inputs(sentiment: 'positive') }.not_to raise_error
      end

      it 'raises error for invalid literal value' do
        expect { literal_sig.validate_inputs(sentiment: 'happy') }
          .to raise_error(Desiru::ValidationError, /sentiment must be one of/)
      end

      it 'validates literal values in arrays' do
        array_sig = described_class.new("responses: List[Literal['yes', 'no']] -> summary: string")
        expect { array_sig.validate_inputs(responses: %w[yes no yes]) }.not_to raise_error
      end

      it 'raises error for invalid literal values in arrays' do
        array_sig = described_class.new("responses: List[Literal['yes', 'no']] -> summary: string")
        expect { array_sig.validate_inputs(responses: %w[yes maybe no]) }
          .to raise_error(Desiru::ValidationError, /responses must be an array of literal values/)
      end
    end
  end

  describe '#coerce_inputs' do
    let(:signature) { described_class.new('question: string, count: int -> answer') }

    it 'coerces input values to correct types' do
      result = signature.coerce_inputs(question: 123, count: '5')
      expect(result[:question]).to eq('123')
      expect(result[:count]).to eq(5)
    end

    it 'preserves correctly typed values' do
      result = signature.coerce_inputs(question: 'What is DSPy?', count: 5)
      expect(result[:question]).to eq('What is DSPy?')
      expect(result[:count]).to eq(5)
    end

    context 'with Literal types' do
      let(:literal_sig) { described_class.new("sentiment: Literal['positive', 'negative', 'neutral'] -> score: float") }

      it 'coerces valid literal values' do
        result = literal_sig.coerce_inputs(sentiment: :positive)
        expect(result[:sentiment]).to eq('positive')
      end

      it 'raises error when coercing invalid literal value' do
        expect { literal_sig.coerce_inputs(sentiment: 'happy') }
          .to raise_error(Desiru::ValidationError, /Value 'happy' is not one of allowed values/)
      end

      it 'coerces literal values in arrays' do
        array_sig = described_class.new("responses: List[Literal['yes', 'no']] -> summary: string")
        result = array_sig.coerce_inputs(responses: [:yes, 'no'])
        expect(result[:responses]).to eq(%w[yes no])
      end

      it 'raises error for invalid literal values in array during coercion' do
        array_sig = described_class.new("responses: List[Literal['yes', 'no']] -> summary: string")
        expect { array_sig.coerce_inputs(responses: ['yes', :maybe]) }
          .to raise_error(Desiru::ValidationError, /Array element 'maybe' is not one of allowed values/)
      end
    end
  end

  describe '#validate_outputs' do
    let(:signature) { described_class.new('question -> answer: string, confidence: float') }

    it 'validates correct outputs' do
      expect { signature.validate_outputs(answer: 'DSPy is a framework', confidence: 0.95) }.not_to raise_error
    end

    it 'raises error for missing required outputs' do
      expect { signature.validate_outputs(answer: 'DSPy is a framework') }
        .to raise_error(Desiru::ValidationError, /Missing required outputs: confidence/)
    end

    it 'raises error for wrong output types' do
      expect { signature.validate_outputs(answer: 'DSPy is a framework', confidence: 'high') }
        .to raise_error(Desiru::ValidationError, /confidence must be a float/)
    end
  end

  describe '#coerce_outputs' do
    let(:signature) { described_class.new('question -> answer: string, confidence: float') }

    it 'coerces output values to correct types' do
      result = signature.coerce_outputs(answer: 123, confidence: '0.95')
      expect(result[:answer]).to eq('123')
      expect(result[:confidence]).to eq(0.95)
    end
  end

  describe '#to_s' do
    it 'returns the original signature string' do
      sig_string = 'question: string -> answer: string'
      sig = described_class.new(sig_string)
      expect(sig.to_s).to eq(sig_string)
    end
  end
end
