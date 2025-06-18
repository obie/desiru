# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Desiru::Field do
  describe '#initialize' do
    it 'creates a field with name and type' do
      field = described_class.new('age', :int)
      expect(field.name).to eq(:age)
      expect(field.type).to eq(:int)
    end

    it 'sets optional to false by default' do
      field = described_class.new('name', :string)
      expect(field.optional?).to be false
    end

    it 'allows setting optional fields' do
      field = described_class.new('nickname', :string, optional: true)
      expect(field.optional?).to be true
    end

    it 'stores description' do
      field = described_class.new('email', :string, description: 'User email address')
      expect(field.description).to eq('User email address')
    end

    it 'stores default value' do
      field = described_class.new('status', :string, default: 'active')
      expect(field.default).to eq('active')
    end
  end

  describe '#validate' do
    context 'with string type' do
      let(:field) { described_class.new('name', :string) }

      it 'accepts string values' do
        expect { field.validate('John') }.not_to raise_error
      end

      it 'rejects non-string values' do
        expect { field.validate(123) }.to raise_error(Desiru::ValidationError, /must be a string/)
      end
    end

    context 'with int type' do
      let(:field) { described_class.new('age', :int) }

      it 'accepts integer values' do
        expect { field.validate(25) }.not_to raise_error
      end

      it 'rejects non-integer values' do
        expect { field.validate('25') }.to raise_error(Desiru::ValidationError, /must be an integer/)
      end
    end

    context 'with float type' do
      let(:field) { described_class.new('price', :float) }

      it 'accepts float values' do
        expect { field.validate(19.99) }.not_to raise_error
      end

      it 'accepts integer values' do
        expect { field.validate(20) }.not_to raise_error
      end

      it 'rejects non-numeric values' do
        expect { field.validate('19.99') }.to raise_error(Desiru::ValidationError, /must be a float/)
      end
    end

    context 'with list type' do
      let(:field) { described_class.new('tags', :list) }

      it 'accepts array values' do
        expect { field.validate(%w[ruby dspy]) }.not_to raise_error
      end

      it 'rejects non-array values' do
        expect { field.validate('ruby,dspy') }.to raise_error(Desiru::ValidationError, /must be a list/)
      end
    end

    context 'with optional fields' do
      let(:field) { described_class.new('nickname', :string, optional: true) }

      it 'accepts nil values' do
        expect { field.validate(nil) }.not_to raise_error
      end

      it 'validates non-nil values' do
        expect { field.validate(123) }.to raise_error(Desiru::ValidationError, /must be a string/)
      end
    end

    context 'with literal type' do
      let(:field) { described_class.new('sentiment', :literal, literal_values: %w[positive negative neutral]) }

      it 'accepts valid literal values' do
        expect { field.validate('positive') }.not_to raise_error
        expect { field.validate('negative') }.not_to raise_error
        expect { field.validate('neutral') }.not_to raise_error
      end

      it 'rejects invalid literal values' do
        expect { field.validate('happy') }.to raise_error(Desiru::ValidationError, /must be one of: positive, negative, neutral/)
      end

      it 'rejects non-string values' do
        expect { field.validate(123) }.to raise_error(Desiru::ValidationError, /must be one of: positive, negative, neutral/)
      end
    end

    context 'with typed array containing literals' do
      let(:field) do
        described_class.new('responses', :list,
                            element_type: { type: :literal, literal_values: %w[yes no] })
      end

      it 'accepts array with valid literal values' do
        expect { field.validate(%w[yes no yes]) }.not_to raise_error
      end

      it 'rejects array with invalid literal values' do
        expect { field.validate(%w[yes maybe no]) }
          .to raise_error(Desiru::ValidationError, /must be an array of literal/)
      end
    end
  end

  describe '#coerce' do
    context 'with string type' do
      let(:field) { described_class.new('name', :string) }

      it 'returns string values unchanged' do
        expect(field.coerce('John')).to eq('John')
      end

      it 'converts other values to string' do
        expect(field.coerce(123)).to eq('123')
        expect(field.coerce(true)).to eq('true')
      end
    end

    context 'with int type' do
      let(:field) { described_class.new('age', :int) }

      it 'returns integer values unchanged' do
        expect(field.coerce(25)).to eq(25)
      end

      it 'converts string numbers to integers' do
        expect(field.coerce('25')).to eq(25)
      end

      it 'converts floats to integers' do
        expect(field.coerce(25.7)).to eq(25)
      end
    end

    context 'with float type' do
      let(:field) { described_class.new('price', :float) }

      it 'returns float values unchanged' do
        expect(field.coerce(19.99)).to eq(19.99)
      end

      it 'converts integers to floats' do
        expect(field.coerce(20)).to eq(20.0)
      end

      it 'converts string numbers to floats' do
        expect(field.coerce('19.99')).to eq(19.99)
      end
    end

    context 'with bool type' do
      let(:field) { described_class.new('active', :bool) }

      it 'returns boolean values unchanged' do
        expect(field.coerce(true)).to be true
        expect(field.coerce(false)).to be false
      end

      it 'converts truthy strings to true' do
        expect(field.coerce('true')).to be true
        expect(field.coerce('yes')).to be true
        expect(field.coerce('1')).to be true
      end

      it 'converts falsy strings to false' do
        expect(field.coerce('false')).to be false
        expect(field.coerce('no')).to be false
        expect(field.coerce('0')).to be false
      end
    end

    context 'with literal type' do
      let(:field) { described_class.new('sentiment', :literal, literal_values: %w[positive negative neutral]) }

      it 'returns valid literal values unchanged' do
        expect(field.coerce('positive')).to eq('positive')
      end

      it 'coerces symbols to strings' do
        expect(field.coerce(:negative)).to eq('negative')
      end

      it 'raises error for invalid literal values' do
        expect { field.coerce('happy') }
          .to raise_error(Desiru::ValidationError, /Value 'happy' is not one of allowed values/)
      end

      it 'coerces non-string values to strings before validation' do
        # This should fail because '123' is not in the allowed values
        expect { field.coerce(123) }
          .to raise_error(Desiru::ValidationError, /Value '123' is not one of allowed values/)
      end
    end

    context 'with typed array containing literals' do
      let(:field) do
        described_class.new('responses', :list,
                            element_type: { type: :literal, literal_values: %w[yes no] })
      end

      it 'coerces array elements to valid literal values' do
        expect(field.coerce([:yes, 'no'])).to eq(%w[yes no])
      end

      it 'raises error for invalid literal values in array' do
        expect { field.coerce(['yes', :maybe]) }
          .to raise_error(Desiru::ValidationError, /Array element 'maybe' is not one of allowed values/)
      end
    end

    context 'with optional fields' do
      let(:field) { described_class.new('nickname', :string, optional: true) }

      it 'returns nil unchanged' do
        expect(field.coerce(nil)).to be_nil
      end

      it 'coerces non-nil values' do
        expect(field.coerce(123)).to eq('123')
      end
    end

    context 'with default values' do
      let(:field) { described_class.new('status', :string, default: 'active') }

      it 'returns default for nil values' do
        expect(field.coerce(nil)).to eq('active')
      end

      it 'coerces non-nil values normally' do
        expect(field.coerce('pending')).to eq('pending')
      end
    end
  end
end
