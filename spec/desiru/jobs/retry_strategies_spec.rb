# frozen_string_literal: true

require 'spec_helper'
require 'desiru/jobs/retry_strategies'

RSpec.describe Desiru::Jobs::RetryStrategies do
  describe Desiru::Jobs::RetryStrategies::ExponentialBackoff do
    subject(:strategy) { described_class.new(base_delay: 2, max_delay: 100, multiplier: 2) }

    describe '#delay_for' do
      it 'calculates exponential delays' do
        expect(strategy.delay_for(0)).to be_within(0.5).of(2)   # 2^0 * 2 = 2
        expect(strategy.delay_for(1)).to be_within(1).of(4)     # 2^1 * 2 = 4
        expect(strategy.delay_for(2)).to be_within(2).of(8)     # 2^2 * 2 = 8
        expect(strategy.delay_for(3)).to be_within(4).of(16)    # 2^3 * 2 = 16
      end

      it 'respects max_delay' do
        expect(strategy.delay_for(10)).to be <= 100
      end

      context 'without jitter' do
        subject(:strategy) { described_class.new(base_delay: 2, jitter: false) }

        it 'returns exact delays' do
          expect(strategy.delay_for(0)).to eq(2)
          expect(strategy.delay_for(1)).to eq(4)
          expect(strategy.delay_for(2)).to eq(8)
        end
      end
    end
  end

  describe Desiru::Jobs::RetryStrategies::LinearBackoff do
    subject(:strategy) { described_class.new(base_delay: 5, increment: 10, max_delay: 50) }

    describe '#delay_for' do
      it 'calculates linear delays' do
        expect(strategy.delay_for(0)).to eq(5)   # 5 + 0*10 = 5
        expect(strategy.delay_for(1)).to eq(15)  # 5 + 1*10 = 15
        expect(strategy.delay_for(2)).to eq(25)  # 5 + 2*10 = 25
        expect(strategy.delay_for(3)).to eq(35)  # 5 + 3*10 = 35
      end

      it 'respects max_delay' do
        expect(strategy.delay_for(10)).to eq(50)
      end
    end
  end

  describe Desiru::Jobs::RetryStrategies::FixedDelay do
    subject(:strategy) { described_class.new(delay: 7) }

    describe '#delay_for' do
      it 'returns the same delay regardless of retry count' do
        expect(strategy.delay_for(0)).to eq(7)
        expect(strategy.delay_for(5)).to eq(7)
        expect(strategy.delay_for(100)).to eq(7)
      end
    end
  end

  describe Desiru::Jobs::RetryStrategies::RetryPolicy do
    let(:strategy) { Desiru::Jobs::RetryStrategies::FixedDelay.new(delay: 1) }
    subject(:policy) { described_class.new(max_retries: 3, retry_strategy: strategy) }

    describe '#retriable?' do
      context 'with retriable_errors specified' do
        subject(:policy) do
          described_class.new(
            retriable_errors: [IOError, RuntimeError]
          )
        end

        it 'retries specified errors' do
          expect(policy.retriable?(IOError.new)).to be true
          expect(policy.retriable?(RuntimeError.new)).to be true
        end

        it 'does not retry unspecified errors' do
          # StandardError and ArgumentError are not in our retriable list
          expect(policy.retriable?(StandardError.new)).to be false
          expect(policy.retriable?(ArgumentError.new)).to be false
        end
      end

      context 'with non_retriable_errors specified' do
        subject(:policy) do
          described_class.new(
            non_retriable_errors: [ArgumentError, NoMethodError]
          )
        end

        it 'does not retry specified errors' do
          expect(policy.retriable?(ArgumentError.new)).to be false
          expect(policy.retriable?(NoMethodError.new)).to be false
        end

        it 'retries other errors' do
          expect(policy.retriable?(StandardError.new)).to be true
        end
      end

      context 'with both retriable and non_retriable specified' do
        subject(:policy) do
          described_class.new(
            retriable_errors: [StandardError],
            non_retriable_errors: [ArgumentError]
          )
        end

        it 'prioritizes non_retriable_errors' do
          # ArgumentError is a StandardError, but it's non-retriable
          expect(policy.retriable?(ArgumentError.new)).to be false
        end
      end
    end

    describe '#should_retry?' do
      it 'returns true when under retry limit and error is retriable' do
        expect(policy.should_retry?(0, StandardError.new)).to be true
        expect(policy.should_retry?(2, StandardError.new)).to be true
      end

      it 'returns false when retry limit is reached' do
        expect(policy.should_retry?(3, StandardError.new)).to be false
        expect(policy.should_retry?(5, StandardError.new)).to be false
      end

      it 'returns false for non-retriable errors' do
        policy = described_class.new(
          max_retries: 5,
          non_retriable_errors: [ArgumentError]
        )
        
        expect(policy.should_retry?(0, ArgumentError.new)).to be false
      end
    end

    describe '#retry_delay' do
      it 'delegates to the retry strategy' do
        expect(strategy).to receive(:delay_for).with(2)
        policy.retry_delay(2)
      end
    end
  end

  describe Desiru::Jobs::RetryStrategies::CircuitBreaker do
    subject(:breaker) { described_class.new(failure_threshold: 3, timeout: 0.1) }

    describe '#call' do
      it 'allows calls when circuit is closed' do
        expect { |b| breaker.call(&b) }.to yield_control
      end

      it 'opens circuit after failure threshold' do
        # Cause failures
        3.times do
          expect { breaker.call { raise 'Error' } }.to raise_error('Error')
        end

        # Circuit should now be open
        expect { breaker.call { 'success' } }
          .to raise_error(Desiru::Jobs::RetryStrategies::CircuitBreaker::CircuitOpenError)
      end

      it 'transitions to half-open after timeout' do
        # Open the circuit
        3.times do
          expect { breaker.call { raise 'Error' } }.to raise_error('Error')
        end

        # Wait for timeout
        sleep 0.15

        # Should allow one request in half-open state
        expect(breaker.call { 'success' }).to eq('success')

        # Circuit should be closed again
        expect(breaker.call { 'success' }).to eq('success')
      end

      it 'reopens circuit on failure in half-open state' do
        # Open the circuit
        3.times do
          expect { breaker.call { raise 'Error' } }.to raise_error('Error')
        end

        # Wait for timeout
        sleep 0.15

        # Fail in half-open state
        expect { breaker.call { raise 'Error' } }.to raise_error('Error')

        # Circuit should be open again
        expect { breaker.call { 'success' } }
          .to raise_error(Desiru::Jobs::RetryStrategies::CircuitBreaker::CircuitOpenError)
      end
    end
  end
end