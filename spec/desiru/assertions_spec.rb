# frozen_string_literal: true

require 'spec_helper'
require 'desiru/assertions'

RSpec.describe Desiru::Assertions do
  describe '.assert' do
    context 'when condition is true' do
      it 'does not raise an error' do
        expect { described_class.assert(true, 'This should pass') }.not_to raise_error
      end
    end

    context 'when condition is false' do
      it 'raises an AssertionError with the provided message' do
        expect { described_class.assert(false, 'Custom error message') }
          .to raise_error(Desiru::Assertions::AssertionError, 'Custom error message')
      end

      it 'raises an AssertionError with default message when no message provided' do
        expect { described_class.assert(false) }
          .to raise_error(Desiru::Assertions::AssertionError, 'Assertion failed')
      end
    end

    context 'when condition is nil' do
      it 'raises an AssertionError' do
        expect { described_class.assert(nil, 'Nil is falsy') }
          .to raise_error(Desiru::Assertions::AssertionError, 'Nil is falsy')
      end
    end
  end

  describe '.suggest' do
    let(:logger) { instance_double(Logger) }

    before do
      allow(Desiru).to receive(:logger).and_return(logger)
    end

    context 'when condition is true' do
      it 'does not log anything' do
        expect(logger).not_to receive(:warn)
        described_class.suggest(true, 'This should not log')
      end
    end

    context 'when condition is false' do
      it 'logs a warning with the provided message' do
        expect(logger).to receive(:warn).with('[SUGGESTION] Custom warning message')
        described_class.suggest(false, 'Custom warning message')
      end

      it 'logs a warning with default message when no message provided' do
        expect(logger).to receive(:warn).with('[SUGGESTION] Suggestion failed')
        described_class.suggest(false)
      end
    end

    context 'when condition is nil' do
      it 'logs a warning' do
        expect(logger).to receive(:warn).with('[SUGGESTION] Nil check failed')
        described_class.suggest(nil, 'Nil check failed')
      end
    end
  end

  describe Desiru::Assertions::AssertionError do
    subject(:error) { described_class.new('Test error', module_name: 'TestModule', retry_count: 2) }

    it 'stores the module name' do
      expect(error.module_name).to eq('TestModule')
    end

    it 'stores the retry count' do
      expect(error.retry_count).to eq(2)
    end

    it 'is retriable' do
      expect(error.retriable?).to be true
    end

    it 'inherits from StandardError' do
      expect(error).to be_a(StandardError)
    end
  end

  describe Desiru::Assertions::Configuration do
    subject(:config) { described_class.new }

    it 'has default max_assertion_retries' do
      expect(config.max_assertion_retries).to eq(3)
    end

    it 'has default assertion_retry_delay' do
      expect(config.assertion_retry_delay).to eq(0.1)
    end

    it 'has default log_assertions enabled' do
      expect(config.log_assertions).to be true
    end

    it 'has default track_assertion_metrics disabled' do
      expect(config.track_assertion_metrics).to be false
    end

    it 'allows configuration changes' do
      config.max_assertion_retries = 5
      config.assertion_retry_delay = 0.5
      config.log_assertions = false
      config.track_assertion_metrics = true

      expect(config.max_assertion_retries).to eq(5)
      expect(config.assertion_retry_delay).to eq(0.5)
      expect(config.log_assertions).to be false
      expect(config.track_assertion_metrics).to be true
    end
  end

  describe '.configure' do
    it 'yields the configuration object' do
      expect { |b| described_class.configure(&b) }.to yield_with_args(described_class.configuration)
    end

    it 'allows configuration through a block' do
      described_class.configure do |config|
        config.max_assertion_retries = 10
        config.assertion_retry_delay = 1.0
      end

      expect(described_class.configuration.max_assertion_retries).to eq(10)
      expect(described_class.configuration.assertion_retry_delay).to eq(1.0)
    end
  end
end

RSpec.describe 'Module-level assertion methods' do
  describe 'Desiru.assert' do
    it 'delegates to Assertions.assert' do
      expect(Desiru::Assertions).to receive(:assert).with(true, 'Test message')
      Desiru.assert(true, 'Test message')
    end

    it 'raises AssertionError when condition is false' do
      expect { Desiru.assert(false, 'Failed assertion') }
        .to raise_error(Desiru::Assertions::AssertionError, 'Failed assertion')
    end
  end

  describe 'Desiru.suggest' do
    it 'delegates to Assertions.suggest' do
      expect(Desiru::Assertions).to receive(:suggest).with(true, 'Test suggestion')
      Desiru.suggest(true, 'Test suggestion')
    end

    it 'logs a warning when condition is false' do
      logger = instance_double(Logger)
      allow(Desiru).to receive(:logger).and_return(logger)
      expect(logger).to receive(:warn).with('[SUGGESTION] Failed suggestion')

      Desiru.suggest(false, 'Failed suggestion')
    end
  end
end
