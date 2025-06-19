# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require 'desiru/jobs/retriable'

RSpec.describe Desiru::Jobs::Retriable do
  # Test job class that includes Retriable
  let(:test_retriable_job_class) do
    Class.new(Desiru::Jobs::Base) do
      include Desiru::Jobs::Retriable

      configure_retries(
        max_retries: 3,
        strategy: Desiru::Jobs::RetryStrategies::FixedDelay.new(delay: 0.1),
        non_retriable: [ArgumentError]
      )

      # Define the base perform method
      def perform_base(_job_id, should_fail = false, error_class = StandardError)
        raise error_class, "Test error" if should_fail

        "Success"
      end

      # Alias it properly for the retriable mixin
      alias perform_without_retries perform_base
      alias perform perform_with_retries
    end
  end

  before do
    stub_const('TestRetriableJob', test_retriable_job_class)
  end

  describe 'retry behavior' do
    let(:job) { TestRetriableJob.new }

    it 'performs job successfully without retries' do
      expect(job.perform('test-123', false)).to eq("Success")
    end

    it 'schedules retry for retriable errors' do
      expect(Desiru.logger).to receive(:warn).with(/Retrying TestRetriableJob/)
      expect(TestRetriableJob).to receive(:perform_in).with(0.1, 'test-123', true, StandardError)

      # Allow the job to handle persistence but mock it
      allow(job).to receive(:persistence_enabled?).and_return(false)

      # The method doesn't re-raise after scheduling retry
      result = job.perform('test-123', true, StandardError)
      expect(result).to be_nil
    end

    it 'does not retry non-retriable errors' do
      expect(TestRetriableJob).not_to receive(:perform_in)
      expect(Desiru.logger).to receive(:error).with(/failed after 0 retries/)

      # Allow the job to handle persistence but mock it
      allow(job).to receive(:persistence_enabled?).and_return(false)
      allow(job).to receive(:persist_error_to_db)

      expect { job.perform('test-123', true, ArgumentError) }
        .to raise_error(ArgumentError)
    end
  end

  describe '.configure_retries' do
    let(:custom_retriable_job_class) do
      Class.new(Desiru::Jobs::Base) do
        include Desiru::Jobs::Retriable
      end
    end

    before do
      stub_const('CustomRetriableJob', custom_retriable_job_class)
    end

    it 'configures retry policy' do
      CustomRetriableJob.configure_retries(
        max_retries: 10,
        retriable: [IOError, Timeout::Error]
      )

      policy = CustomRetriableJob.retry_policy
      expect(policy.max_retries).to eq(10)
      expect(policy.retriable?(IOError.new)).to be true
      expect(policy.retriable?(StandardError.new)).to be false
    end
  end

  describe Desiru::Jobs::RetriableJob do
    it 'has default retry configuration' do
      policy = described_class.retry_policy

      expect(policy.max_retries).to eq(5)
      expect(policy.retry_strategy).to be_a(Desiru::Jobs::RetryStrategies::ExponentialBackoff)
      expect(policy.retriable?(StandardError.new)).to be true
      expect(policy.retriable?(ArgumentError.new)).to be false
    end
  end
end
