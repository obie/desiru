# frozen_string_literal: true

require 'spec_helper'
require 'support/database_helper'

RSpec.describe Desiru::Persistence::Repositories::JobResultRepository, :persistence do

  let(:repository) { described_class.new }

  before do
    # Clean up any existing job results
    Desiru::Persistence::Models::JobResult.dataset.delete
  end

  describe '#create_for_job' do
    it 'creates a new job result with pending status' do
      job_result = repository.create_for_job(
        'test-job-123',
        'TestJob',
        'default',
        inputs: { text: 'Hello world' },
        expires_at: Time.now + 3600
      )

      expect(job_result).to be_a(Desiru::Persistence::Models::JobResult)
      expect(job_result.job_id).to eq('test-job-123')
      expect(job_result.job_class).to eq('TestJob')
      expect(job_result.queue).to eq('default')
      expect(job_result.status).to eq('pending')
      expect(job_result.inputs_data).to eq(text: 'Hello world')
      expect(job_result.expires_at).to be_within(5).of(Time.now + 3600)
    end
  end

  describe '#find_by_job_id' do
    it 'finds job result by job_id' do
      created = repository.create_for_job('find-test-123', 'TestJob', 'default')
      found = repository.find_by_job_id('find-test-123')

      expect(found).to eq(created)
    end

    it 'returns nil if not found' do
      expect(repository.find_by_job_id('non-existent')).to be_nil
    end
  end

  describe '#mark_processing' do
    it 'marks job as processing' do
      repository.create_for_job('process-test', 'TestJob', 'default')

      updated = repository.mark_processing('process-test')

      expect(updated.status).to eq('processing')
      expect(updated.started_at).not_to be_nil
    end

    it 'returns nil if job not found' do
      expect(repository.mark_processing('non-existent')).to be_nil
    end
  end

  describe '#mark_completed' do
    it 'marks job as completed with result' do
      repository.create_for_job('complete-test', 'TestJob', 'default')
      repository.mark_processing('complete-test')

      result_data = { output: 'Success', score: 0.99 }
      updated = repository.mark_completed('complete-test', result_data, message: 'All done')

      expect(updated.status).to eq('completed')
      expect(updated.progress).to eq(100)
      expect(updated.finished_at).not_to be_nil
      expect(updated.result_data).to eq(output: 'Success', score: 0.99)
      expect(updated.message).to eq('All done')
    end
  end

  describe '#mark_failed' do
    it 'marks job as failed with error information' do
      repository.create_for_job('fail-test', 'TestJob', 'default')
      repository.mark_processing('fail-test')

      error = StandardError.new('Test error')
      backtrace = ['file.rb:10:in method', 'file.rb:20:in call']

      updated = repository.mark_failed('fail-test', error, backtrace: backtrace)

      expect(updated.status).to eq('failed')
      expect(updated.finished_at).not_to be_nil
      expect(updated.error_message).to eq('Test error')
      expect(updated.error_backtrace).to include('file.rb:10:in method')
      expect(updated.retry_count).to eq(1)
    end

    it 'increments retry count by default' do
      job_result = repository.create_for_job('retry-test', 'TestJob', 'default')

      # First failure
      repository.mark_failed('retry-test', 'Error 1')
      job_result.reload
      expect(job_result.retry_count).to eq(1)

      # Second failure
      repository.mark_failed('retry-test', 'Error 2')
      job_result.reload
      expect(job_result.retry_count).to eq(2)
    end

    it 'does not increment retry count when specified' do
      repository.create_for_job('no-retry-test', 'TestJob', 'default')

      repository.mark_failed('no-retry-test', 'Error', increment_retry: false)
      job_result = repository.find_by_job_id('no-retry-test')

      expect(job_result.retry_count).to eq(0)
    end
  end

  describe '#update_progress' do
    it 'updates progress and message' do
      repository.create_for_job('progress-test', 'TestJob', 'default')
      repository.mark_processing('progress-test')

      updated = repository.update_progress('progress-test', 50, message: 'Halfway there')

      expect(updated.progress).to eq(50)
      expect(updated.message).to eq('Halfway there')
    end
  end

  describe '#cleanup_expired' do
    before do
      # Create expired job
      repository.create_for_job(
        'expired-job',
        'TestJob',
        'default',
        expires_at: Time.now - 100
      )

      # Create active job
      repository.create_for_job(
        'active-job',
        'TestJob',
        'default',
        expires_at: Time.now + 100
      )

      # Create job without expiration
      repository.create_for_job('no-expire-job', 'TestJob', 'default')
    end

    it 'removes expired jobs' do
      expect(repository.count).to eq(3)

      repository.cleanup_expired

      expect(repository.count).to eq(2)
      expect(repository.find_by_job_id('expired-job')).to be_nil
      expect(repository.find_by_job_id('active-job')).not_to be_nil
      expect(repository.find_by_job_id('no-expire-job')).not_to be_nil
    end
  end

  describe '#recent_by_class' do
    before do
      5.times do |i|
        repository.create_for_job(
          "test-job-#{i}",
          'TestJob',
          'default'
        )
        sleep 0.01 # Ensure different timestamps
      end

      3.times do |i|
        repository.create_for_job(
          "other-job-#{i}",
          'OtherJob',
          'default'
        )
        sleep 0.01
      end
    end

    it 'returns recent jobs by class' do
      results = repository.recent_by_class('TestJob', limit: 3)

      expect(results.size).to eq(3)
      expect(results.map(&:job_class).uniq).to eq(['TestJob'])
      expect(results.map(&:job_id)).to eq(%w[test-job-4 test-job-3 test-job-2])
    end
  end

  describe '#statistics' do
    before do
      # Create various job states
      repository.create_for_job('stat-pending', 'TestJob', 'default')

      repository.create_for_job('stat-processing', 'TestJob', 'default')
      repository.mark_processing('stat-processing')

      repository.create_for_job('stat-completed-1', 'TestJob', 'default')
      repository.mark_processing('stat-completed-1')
      sleep 0.1 # Ensure there's a measurable duration
      repository.mark_completed('stat-completed-1', { result: 'ok' })

      repository.create_for_job('stat-completed-2', 'OtherJob', 'default')
      repository.mark_processing('stat-completed-2')
      sleep 0.1 # Ensure there's a measurable duration
      repository.mark_completed('stat-completed-2', { result: 'ok' })

      repository.create_for_job('stat-failed', 'TestJob', 'default')
      repository.mark_processing('stat-failed')
      repository.mark_failed('stat-failed', 'Error')
    end

    it 'returns overall statistics' do
      stats = repository.statistics

      expect(stats[:total]).to eq(5)
      expect(stats[:pending]).to eq(1)
      expect(stats[:processing]).to eq(1)
      expect(stats[:completed]).to eq(2)
      expect(stats[:failed]).to eq(1)

      # Check that average duration is calculated (may be very small in test environment)
      expect(stats[:average_duration]).to be > 0.05
    end

    it 'filters statistics by job class' do
      stats = repository.statistics(job_class: 'TestJob')

      expect(stats[:total]).to eq(4)
      expect(stats[:completed]).to eq(1)
    end

    it 'filters statistics by time' do
      # Create an old job
      old_job = repository.create_for_job('old-job', 'TestJob', 'default')
      old_job.update(created_at: Time.now - 7200) # 2 hours ago

      stats = repository.statistics(since: Time.now - 3600) # Last hour

      expect(stats[:total]).to eq(5) # Excludes the old job
    end
  end
end
