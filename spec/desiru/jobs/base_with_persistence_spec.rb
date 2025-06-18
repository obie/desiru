# frozen_string_literal: true

require 'spec_helper'
require 'support/database_helper'
require 'desiru/persistence/setup'

RSpec.describe Desiru::Jobs::Base, :persistence do
  # Force a new database connection for this test file
  before(:all) do
    DatabaseHelper.setup_connection(force_new: true)
  end

  # Test job class that uses the base functionality
  class TestPersistenceJob < described_class
    def perform(job_id, inputs)
      # Create job record when starting
      create_job_record(job_id, inputs: inputs)

      # Mark as processing
      update_status(job_id, 'processing', progress: 0)

      # Simulate work
      sleep 0.1
      update_status(job_id, 'processing', progress: 50, message: 'Halfway done')

      # Complete the job
      result = { output: "Processed: #{inputs[:text]}", timestamp: Time.now.iso8601 }
      store_result(job_id, result)
      update_status(job_id, 'completed', progress: 100)

      result
    end
  end

  class TestFailingJob < described_class
    def perform(job_id)
      create_job_record(job_id)
      update_status(job_id, 'processing')

      # Simulate failure
      error = StandardError.new('Simulated job failure')
      persist_error_to_db(job_id, error, caller)
      update_status(job_id, 'failed')

      raise error
    end
  end

  let(:redis) { Redis.new }
  let(:job_repo) { Desiru::Persistence.repositories[:job_results] }

  before do
    redis.flushdb
    # DatabaseHelper handles database cleanup for :persistence tagged tests
  end

  describe 'with persistence enabled' do
    before do
      allow(Desiru::Persistence).to receive(:enabled?).and_return(true)
    end

    describe '#store_result' do
      it 'stores result in both Redis and database' do
        job = TestPersistenceJob.new
        job_id = 'test-store-123'
        result = { output: 'test result' }

        # Create the job record first
        job.send(:create_job_record, job_id)

        # Store the result
        job.send(:store_result, job_id, result)

        # Check Redis
        redis_result = JSON.parse(redis.get("desiru:results:#{job_id}"), symbolize_names: true)
        expect(redis_result).to eq(result)

        # Check database
        db_record = job_repo.find_by_job_id(job_id)
        expect(db_record).not_to be_nil
        expect(db_record.status).to eq('completed')
        expect(db_record.result_data).to eq(result)
      end
    end

    describe '#update_status' do
      it 'updates status in both Redis and database' do
        job = TestPersistenceJob.new
        job_id = 'test-status-123'

        # Create the job record first
        job.send(:create_job_record, job_id)

        # Update status
        job.send(:update_status, job_id, 'processing', progress: 25, message: 'Starting work')

        # Check Redis
        redis_status = JSON.parse(redis.get("desiru:status:#{job_id}"), symbolize_names: true)
        expect(redis_status[:status]).to eq('processing')
        expect(redis_status[:progress]).to eq(25)
        expect(redis_status[:message]).to eq('Starting work')

        # Check database
        db_record = job_repo.find_by_job_id(job_id)
        expect(db_record.status).to eq('processing')
        expect(db_record.progress).to eq(25)
        expect(db_record.message).to eq('Starting work')
      end
    end

    describe '#create_job_record' do
      it 'creates a job record in the database' do
        job = TestPersistenceJob.new
        job_id = 'test-create-123'
        inputs = { text: 'Hello world', count: 5 }
        expires_at = Time.now + 3600

        job.send(:create_job_record, job_id, inputs: inputs, expires_at: expires_at)

        db_record = job_repo.find_by_job_id(job_id)
        expect(db_record).not_to be_nil
        expect(db_record.job_class).to eq('TestPersistenceJob')
        expect(db_record.queue).to eq('default')
        expect(db_record.status).to eq('pending')
        expect(db_record.inputs_data).to eq(text: 'Hello world', count: 5)
        expect(db_record.expires_at).to be_within(5).of(expires_at)
      end
    end

    describe '#persist_error_to_db' do
      it 'persists error information to database' do
        job = TestFailingJob.new
        job_id = 'test-error-123'

        # Create the job record first
        job.send(:create_job_record, job_id)

        # Persist error
        error = RuntimeError.new('Test error message')
        backtrace = ['file.rb:10:in method', 'file.rb:20:in block']

        job.send(:persist_error_to_db, job_id, error, backtrace)

        db_record = job_repo.find_by_job_id(job_id)
        expect(db_record.status).to eq('failed')
        expect(db_record.error_message).to eq('Test error message')
        expect(db_record.error_backtrace).to eq("file.rb:10:in method\nfile.rb:20:in block")
        expect(db_record.retry_count).to eq(1)
      end
    end

    describe 'full job lifecycle' do
      it 'tracks successful job execution' do
        job = TestPersistenceJob.new
        job_id = 'lifecycle-success-123'
        inputs = { text: 'Test input' }

        job.perform(job_id, inputs)

        # Check final database state
        db_record = job_repo.find_by_job_id(job_id)
        expect(db_record.status).to eq('completed')
        expect(db_record.progress).to eq(100)
        expect(db_record.inputs_data).to eq(inputs)
        expect(db_record.result_data[:output]).to eq('Processed: Test input')
        expect(db_record.started_at).not_to be_nil
        expect(db_record.finished_at).not_to be_nil
        expect(db_record.duration).to be > 0
      end

      it 'tracks failed job execution' do
        job = TestFailingJob.new
        job_id = 'lifecycle-fail-123'

        expect { job.perform(job_id) }.to raise_error(StandardError, 'Simulated job failure')

        # Check final database state
        db_record = job_repo.find_by_job_id(job_id)
        expect(db_record.status).to eq('failed')
        expect(db_record.error_message).to eq('Simulated job failure')
        expect(db_record.error_backtrace).not_to be_nil
        expect(db_record.started_at).not_to be_nil
      end
    end
  end

  describe 'with persistence disabled' do
    before do
      allow(Desiru::Persistence).to receive(:enabled?).and_return(false)
    end

    it 'still stores results in Redis' do
      job = TestPersistenceJob.new
      job_id = 'test-no-persist-123'
      result = { output: 'test result' }

      job.send(:store_result, job_id, result)

      # Check Redis
      redis_result = JSON.parse(redis.get("desiru:results:#{job_id}"), symbolize_names: true)
      expect(redis_result).to eq(result)

      # Check database is empty
      expect(job_repo.find_by_job_id(job_id)).to be_nil
    end

    it 'handles persistence errors gracefully' do
      job = TestPersistenceJob.new
      allow(Desiru::Persistence).to receive(:enabled?).and_raise('Database connection error')

      # Should not raise error
      expect { job.send(:create_job_record, 'test-123') }.not_to raise_error
      expect { job.send(:update_status, 'test-123', 'processing') }.not_to raise_error
      expect { job.send(:store_result, 'test-123', { result: 'ok' }) }.not_to raise_error
    end
  end
end
