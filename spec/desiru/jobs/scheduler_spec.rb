# frozen_string_literal: true

require 'spec_helper'
require 'desiru/jobs/scheduler'

RSpec.describe Desiru::Jobs::Scheduler do
  let(:scheduler) { described_class.instance }
  let(:test_job_class) do
    Class.new do
      def self.name
        'TestJob'
      end

      def self.perform_async(*args)
        # Mock implementation
      end
    end
  end

  before do
    scheduler.clear
    scheduler.stop if scheduler.running?
  end

  after do
    scheduler.stop if scheduler.running?
    scheduler.clear
  end

  describe '#schedule' do
    it 'adds a job to the schedule' do
      scheduler.schedule('test_job', job_class: test_job_class, cron: '60')

      job_info = scheduler.job_info('test_job')
      expect(job_info).not_to be_nil
      expect(job_info[:job_class]).to eq(test_job_class)
      expect(job_info[:cron]).to eq('60')
      expect(job_info[:next_run]).to be_a(Time)
    end

    it 'schedules with arguments' do
      args = %w[arg1 arg2]
      scheduler.schedule('test_job', job_class: test_job_class, cron: '60', args: args)

      job_info = scheduler.job_info('test_job')
      expect(job_info[:args]).to eq(args)
    end

    it 'overwrites existing scheduled job with same name' do
      scheduler.schedule('test_job', job_class: test_job_class, cron: '60')
      scheduler.schedule('test_job', job_class: test_job_class, cron: '120')

      job_info = scheduler.job_info('test_job')
      expect(job_info[:cron]).to eq('120')
    end
  end

  describe '#unschedule' do
    it 'removes a job from the schedule' do
      scheduler.schedule('test_job', job_class: test_job_class, cron: '60')
      expect(scheduler.job_info('test_job')).not_to be_nil

      scheduler.unschedule('test_job')
      expect(scheduler.job_info('test_job')).to be_nil
    end
  end

  describe '#start and #stop' do
    it 'starts and stops the scheduler' do
      expect(scheduler.running?).to be false

      scheduler.start
      expect(scheduler.running?).to be true

      scheduler.stop
      expect(scheduler.running?).to be false
    end

    it 'does not start multiple times' do
      scheduler.start
      thread1 = scheduler.instance_variable_get(:@thread)

      scheduler.start
      thread2 = scheduler.instance_variable_get(:@thread)

      expect(thread1).to eq(thread2)
    end
  end

  describe 'job execution' do
    it 'executes jobs at the scheduled time' do
      allow(test_job_class).to receive(:perform_async)

      # Schedule a job to run immediately (1 second interval)
      scheduler.schedule('test_job', job_class: test_job_class, cron: '1')
      scheduler.start

      # Wait for the job to be executed
      sleep 1.5

      expect(test_job_class).to have_received(:perform_async).at_least(:once)
    end

    it 'passes arguments to the job' do
      allow(test_job_class).to receive(:perform_async)

      args = %w[arg1 arg2]
      scheduler.schedule('test_job', job_class: test_job_class, cron: '1', args: args)
      scheduler.start

      sleep 1.5

      expect(test_job_class).to have_received(:perform_async).with(anything, *args).at_least(:once)
    end

    it 'handles job execution errors gracefully' do
      allow(test_job_class).to receive(:perform_async).and_raise(StandardError, 'Job error')
      allow(Desiru.logger).to receive(:error)

      scheduler.schedule('test_job', job_class: test_job_class, cron: '1')
      scheduler.start

      sleep 1.5

      expect(Desiru.logger).to have_received(:error).with(/Failed to enqueue scheduled job/)
    end
  end

  describe 'cron expression parsing' do
    let(:now) { Time.now }

    context 'simple interval in seconds' do
      it 'calculates next run time for numeric intervals' do
        scheduler.schedule('test_job', job_class: test_job_class, cron: '30')
        job_info = scheduler.job_info('test_job')

        expect(job_info[:next_run]).to be_within(1).of(now + 30)
      end
    end

    context 'interval expressions' do
      it 'handles "every N seconds"' do
        scheduler.schedule('test_job', job_class: test_job_class, cron: 'every 10 seconds')
        job_info = scheduler.job_info('test_job')

        expect(job_info[:next_run]).to be_within(1).of(now + 10)
      end

      it 'handles "every N minutes"' do
        scheduler.schedule('test_job', job_class: test_job_class, cron: 'every 5 minutes')
        job_info = scheduler.job_info('test_job')

        expect(job_info[:next_run]).to be_within(1).of(now + 300)
      end

      it 'handles "every N hours"' do
        scheduler.schedule('test_job', job_class: test_job_class, cron: 'every 2 hours')
        job_info = scheduler.job_info('test_job')

        expect(job_info[:next_run]).to be_within(1).of(now + 7200)
      end

      it 'handles "every N days"' do
        scheduler.schedule('test_job', job_class: test_job_class, cron: 'every 1 day')
        job_info = scheduler.job_info('test_job')

        expect(job_info[:next_run]).to be_within(1).of(now + 86_400)
      end
    end

    context 'cron expressions' do
      it 'handles "* * * * *" (every minute)' do
        scheduler.schedule('test_job', job_class: test_job_class, cron: '* * * * *')
        job_info = scheduler.job_info('test_job')

        expect(job_info[:next_run]).to be_within(1).of(now + 60)
      end

      it 'handles "0 * * * *" (every hour)' do
        scheduler.schedule('test_job', job_class: test_job_class, cron: '0 * * * *')
        job_info = scheduler.job_info('test_job')

        # Should run at the next hour mark
        next_hour = Time.new(now.year, now.month, now.day, now.hour, 0, 0) + 3600
        expect(job_info[:next_run]).to be_within(61).of(next_hour)
      end

      it 'handles "30 10 * * *" (daily at 10:30)' do
        scheduler.schedule('test_job', job_class: test_job_class, cron: '30 10 * * *')
        job_info = scheduler.job_info('test_job')

        target_time = Time.new(now.year, now.month, now.day, 10, 30, 0)
        # If already past 10:30 today, should be tomorrow
        target_time += 86_400 if target_time <= now

        expect(job_info[:next_run]).to eq(target_time)
      end

      it 'defaults to hourly for invalid cron expressions' do
        allow(Desiru.logger).to receive(:warn)

        scheduler.schedule('test_job', job_class: test_job_class, cron: 'invalid')
        job_info = scheduler.job_info('test_job')

        expect(job_info[:next_run]).to be_within(1).of(now + 3600)
        expect(Desiru.logger).to have_received(:warn).with(/Invalid cron expression/)
      end
    end
  end

  describe '#clear' do
    it 'removes all scheduled jobs' do
      scheduler.schedule('job1', job_class: test_job_class, cron: '60')
      scheduler.schedule('job2', job_class: test_job_class, cron: '120')

      expect(scheduler.jobs.size).to eq(2)

      scheduler.clear

      expect(scheduler.jobs.size).to eq(0)
    end
  end
end

RSpec.describe Desiru::Jobs::Schedulable do
  let(:job_class) do
    Class.new do
      include Desiru::Jobs::Schedulable

      def self.name
        'SchedulableTestJob'
      end

      def self.perform_async(*args)
        # Mock implementation
      end
    end
  end

  let(:scheduler) { Desiru::Jobs::Scheduler.instance }

  before do
    scheduler.clear
  end

  after do
    scheduler.clear
  end

  describe '.schedule' do
    it 'schedules the job with the scheduler' do
      job_class.schedule(cron: '60')

      job_info = scheduler.job_info('SchedulableTestJob')
      expect(job_info).not_to be_nil
      expect(job_info[:job_class]).to eq(job_class)
      expect(job_info[:cron]).to eq('60')
    end

    it 'allows custom job name' do
      job_class.schedule(name: 'custom_name', cron: '60')

      expect(scheduler.job_info('custom_name')).not_to be_nil
      expect(scheduler.job_info('SchedulableTestJob')).to be_nil
    end

    it 'passes arguments to the scheduler' do
      args = %w[arg1 arg2]
      job_class.schedule(cron: '60', args: args)

      job_info = scheduler.job_info('SchedulableTestJob')
      expect(job_info[:args]).to eq(args)
    end
  end

  describe '.unschedule' do
    it 'removes the job from the scheduler' do
      job_class.schedule(cron: '60')
      expect(job_class.scheduled?).to be true

      job_class.unschedule
      expect(job_class.scheduled?).to be false
    end

    it 'unschedules by custom name' do
      job_class.schedule(name: 'custom_name', cron: '60')
      job_class.unschedule(name: 'custom_name')

      expect(scheduler.job_info('custom_name')).to be_nil
    end
  end

  describe '.scheduled?' do
    it 'returns true when job is scheduled' do
      job_class.schedule(cron: '60')
      expect(job_class.scheduled?).to be true
    end

    it 'returns false when job is not scheduled' do
      expect(job_class.scheduled?).to be false
    end

    it 'checks by custom name' do
      job_class.schedule(name: 'custom_name', cron: '60')
      expect(job_class.scheduled?(name: 'custom_name')).to be true
      expect(job_class.scheduled?).to be false
    end
  end
end
