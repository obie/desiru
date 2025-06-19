# frozen_string_literal: true

RSpec.describe Desiru do
  it 'has a version number' do
    expect(Desiru::VERSION).not_to be_nil
  end

  describe '.configure' do
    it 'yields configuration block' do
      expect { |b| described_class.configure(&b) }.to yield_with_args(Desiru::Configuration)
    end

    it 'allows setting default model' do
      model = double('model')
      described_class.configure do |config|
        config.default_model = model
      end
      expect(described_class.configuration.default_model).to eq(model)
    end
  end

  describe '.configuration' do
    it 'returns the configuration instance' do
      expect(described_class.configuration).to be_a(Desiru::Configuration)
    end
  end
end
