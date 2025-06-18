# frozen_string_literal: true

require 'spec_helper'
require 'support/database_helper'
require 'desiru/persistence'

# Ensure the database is connected and setup before trying to describe the model
RSpec.describe 'Desiru::Persistence::Models::JobResult', :persistence do
  # Get the actual class after database setup
  let(:model_class) { Desiru::Persistence::Models::JobResult }

  before do
    # Clean up any existing job results
    model_class.dataset.delete
  end

  describe 'validations' do
    it 'requires job_id' do
      job_result = model_class.new(
        job_class: 'TestJob',
        queue: 'default',
        status: 'pending',
        enqueued_at: Time.now
      )
      expect(job_result.valid?).to be false
      expect(job_result.errors[:job_id]).to include('is not present')
    end

    it 'requires job_id to be unique' do
      model_class.create(
        job_id: 'unique-job-123',
        job_class: 'TestJob',
        queue: 'default',
        status: 'pending',
        enqueued_at: Time.now
      )

      duplicate = model_class.new(
        job_id: 'unique-job-123',
        job_class: 'AnotherJob',
        queue: 'default',
        status: 'pending',
        enqueued_at: Time.now
      )

      expect(duplicate.valid?).to be false
      expect(duplicate.errors[:job_id]).to include('is already taken')
    end

    it 'validates status inclusion' do
      job_result = model_class.new(
        job_id: 'test-123',
        job_class: 'TestJob',
        queue: 'default',
        status: 'invalid',
        enqueued_at: Time.now
      )
      expect(job_result.valid?).to be false
      expect(job_result.errors[:status]).to include('is not in range or set: ["pending", "processing", "completed", "failed"]')
    end
  end

  describe 'status methods' do
    let(:job_result) do
      model_class.create(
        job_id: 'status-test-123',
        job_class: 'TestJob',
        queue: 'default',
        status: 'pending',
        enqueued_at: Time.now
      )
    end

    it 'correctly identifies pending status' do
      expect(job_result.pending?).to be true
      expect(job_result.processing?).to be false
      expect(job_result.completed?).to be false
      expect(job_result.failed?).to be false
    end

    it 'correctly identifies processing status' do
      job_result.update(status: 'processing')
      expect(job_result.processing?).to be true
      expect(job_result.pending?).to be false
    end

    it 'correctly identifies completed status' do
      job_result.update(status: 'completed')
      expect(job_result.completed?).to be true
      expect(job_result.pending?).to be false
    end

    it 'correctly identifies failed status' do
      job_result.update(status: 'failed')
      expect(job_result.failed?).to be true
      expect(job_result.pending?).to be false
    end
  end

  describe '#duration' do
    it 'returns nil if not started' do
      job_result = model_class.create(
        job_id: 'duration-test-1',
        job_class: 'TestJob',
        queue: 'default',
        status: 'pending',
        enqueued_at: Time.now
      )
      expect(job_result.duration).to be_nil
    end

    it 'returns nil if not finished' do
      job_result = model_class.create(
        job_id: 'duration-test-2',
        job_class: 'TestJob',
        queue: 'default',
        status: 'processing',
        enqueued_at: Time.now,
        started_at: Time.now
      )
      expect(job_result.duration).to be_nil
    end

    it 'calculates duration when started and finished' do
      started = Time.now
      finished = started + 10.5

      job_result = model_class.create(
        job_id: 'duration-test-3',
        job_class: 'TestJob',
        queue: 'default',
        status: 'completed',
        enqueued_at: started - 5,
        started_at: started,
        finished_at: finished
      )

      expect(job_result.duration).to be_within(0.1).of(10.5)
    end
  end

  describe '#mark_as_processing!' do
    let(:job_result) do
      model_class.create(
        job_id: 'processing-test',
        job_class: 'TestJob',
        queue: 'default',
        status: 'pending',
        enqueued_at: Time.now
      )
    end

    it 'updates status and started_at' do
      expect { job_result.mark_as_processing! }.to change {
        [job_result.status, job_result.started_at.nil?, job_result.progress]
      }.from(['pending', true, 0]).to(['processing', false, 0])
    end
  end

  describe '#mark_as_completed!' do
    let(:job_result) do
      model_class.create(
        job_id: 'completed-test',
        job_class: 'TestJob',
        queue: 'default',
        status: 'processing',
        enqueued_at: Time.now,
        started_at: Time.now
      )
    end

    it 'updates status, result, and finished_at' do
      result_data = { output: 'test result', score: 0.95 }

      job_result.mark_as_completed!(result_data, message: 'Job completed successfully')

      expect(job_result.status).to eq('completed')
      expect(job_result.progress).to eq(100)
      expect(job_result.finished_at).not_to be_nil
      expect(job_result.result_data).to eq(output: 'test result', score: 0.95)
      expect(job_result.message).to eq('Job completed successfully')
    end
  end

  describe '#mark_as_failed!' do
    let(:job_result) do
      model_class.create(
        job_id: 'failed-test',
        job_class: 'TestJob',
        queue: 'default',
        status: 'processing',
        enqueued_at: Time.now,
        started_at: Time.now
      )
    end

    it 'updates status and error information' do
      error = StandardError.new('Something went wrong')
      backtrace = %w[line1 line2 line3]

      job_result.mark_as_failed!(error, backtrace: backtrace)

      expect(job_result.status).to eq('failed')
      expect(job_result.finished_at).not_to be_nil
      expect(job_result.error_message).to eq('Something went wrong')
      expect(job_result.error_backtrace).to eq("line1\nline2\nline3")
    end
  end

  describe 'scopes' do
    before do
      # Create various job results
      model_class.create(
        job_id: 'scope-pending',
        job_class: 'TestJob',
        queue: 'default',
        status: 'pending',
        enqueued_at: Time.now
      )

      model_class.create(
        job_id: 'scope-processing',
        job_class: 'TestJob',
        queue: 'critical',
        status: 'processing',
        enqueued_at: Time.now,
        started_at: Time.now
      )

      model_class.create(
        job_id: 'scope-completed',
        job_class: 'OtherJob',
        queue: 'default',
        status: 'completed',
        enqueued_at: Time.now - 100,
        started_at: Time.now - 95,
        finished_at: Time.now - 90
      )

      model_class.create(
        job_id: 'scope-failed',
        job_class: 'TestJob',
        queue: 'low',
        status: 'failed',
        enqueued_at: Time.now - 200,
        started_at: Time.now - 195,
        finished_at: Time.now - 190,
        error_message: 'Test error'
      )

      model_class.create(
        job_id: 'scope-expired',
        job_class: 'TestJob',
        queue: 'default',
        status: 'completed',
        enqueued_at: Time.now - 300,
        expires_at: Time.now - 100
      )
    end

    it 'filters by status' do
      expect(model_class.pending.count).to eq(1)
      expect(model_class.processing.count).to eq(1)
      expect(model_class.completed.count).to eq(2)
      expect(model_class.failed.count).to eq(1)
    end

    it 'filters by job class' do
      expect(model_class.by_job_class('TestJob').count).to eq(4)
      expect(model_class.by_job_class('OtherJob').count).to eq(1)
    end

    it 'filters expired jobs' do
      expect(model_class.expired.count).to eq(1)
      expect(model_class.active.count).to eq(4)
    end

    it 'orders by recent' do
      # Wait a bit to ensure different timestamps
      sleep 0.01

      # Create a new recent job to test ordering
      model_class.create(
        job_id: 'scope-very-recent',
        job_class: 'TestJob',
        queue: 'default',
        status: 'pending',
        enqueued_at: Time.now
      )

      recent = model_class.recent(3).map(&:job_id)
      expect(recent.first).to eq('scope-very-recent')
      expect(recent.size).to eq(3)
    end
  end
end
