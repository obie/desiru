# frozen_string_literal: true

require 'singleton'

module Desiru
  module Jobs
    # Simple cron-like scheduler for Sidekiq jobs
    class Scheduler
      include Singleton

      attr_reader :jobs

      def initialize
        @jobs = {}
        @running = false
        @thread = nil
      end

      # Schedule a job to run periodically
      # @param name [String] unique name for the scheduled job
      # @param job_class [Class] the job class to execute
      # @param cron [String] cron expression or simple interval
      # @param args [Array] arguments to pass to the job
      # @param options [Hash] additional options
      def schedule(name, job_class:, cron:, args: [], **options)
        @jobs[name] = {
          job_class: job_class,
          cron: cron,
          args: args,
          options: options,
          last_run: nil,
          next_run: calculate_next_run(cron, nil)
        }
      end

      # Remove a scheduled job
      def unschedule(name)
        @jobs.delete(name)
      end

      # Start the scheduler
      def start
        return if @running

        @running = true
        @thread = Thread.new do
          while @running
            check_and_run_jobs
            sleep 1 # Check every second
          end
        end
      end

      # Stop the scheduler
      def stop
        @running = false
        @thread&.join
      end

      # Check if scheduler is running
      def running?
        @running
      end

      # Clear all scheduled jobs
      def clear
        @jobs.clear
      end

      # Get information about a scheduled job
      def job_info(name)
        @jobs[name]
      end

      private

      def check_and_run_jobs
        current_time = Time.now

        @jobs.each do |name, job_config|
          next unless should_run?(job_config, current_time)

          run_job(name, job_config)
          job_config[:last_run] = current_time
          job_config[:next_run] = calculate_next_run(job_config[:cron], current_time)
        end
      rescue StandardError => e
        Desiru.logger.error("Scheduler error: #{e.message}")
      end

      def should_run?(job_config, current_time)
        job_config[:next_run] && current_time >= job_config[:next_run]
      end

      def run_job(name, job_config)
        job_class = job_config[:job_class]
        args = job_config[:args]

        # Generate unique job ID for scheduled jobs
        job_id = "scheduled-#{name}-#{Time.now.to_i}"

        # Enqueue the job
        if job_class.respond_to?(:perform_async)
          if args.empty?
            job_class.perform_async(job_id)
          else
            job_class.perform_async(job_id, *args)
          end

          Desiru.logger.info("Scheduled job #{name} enqueued with ID: #{job_id}")
        else
          Desiru.logger.error("Job class #{job_class} does not respond to perform_async")
        end
      rescue StandardError => e
        Desiru.logger.error("Failed to enqueue scheduled job #{name}: #{e.message}")
      end

      def calculate_next_run(cron_expression, last_run)
        case cron_expression
        when /^\d+$/ # Simple interval in seconds
          interval = cron_expression.to_i
          base_time = last_run || Time.now
          base_time + interval
        when /^every (\d+) (second|minute|hour|day)s?$/i
          # Handle simple interval expressions like "every 5 minutes"
          amount = ::Regexp.last_match(1).to_i
          unit = ::Regexp.last_match(2).downcase

          interval = case unit
                     when 'second' then amount
                     when 'minute' then amount * 60
                     when 'hour' then amount * 3600
                     when 'day' then amount * 86_400
                     end

          base_time = last_run || Time.now
          base_time + interval
        else
          # For now, we'll support simple cron patterns
          parse_cron_expression(cron_expression, last_run)
        end
      end

      def parse_cron_expression(cron_expression, last_run)
        # Simple cron parser for common patterns
        # Format: minute hour day month weekday
        parts = cron_expression.split(' ')

        case parts.length
        when 5
          # Full cron expression - for now, just support simple patterns
          minute, hour, = parts

          if minute == '*' && hour == '*'
            # Every minute
            (last_run || Time.now) + 60
          elsif minute =~ /^\d+$/ && hour == '*'
            # Every hour at specific minute
            next_time = last_run || Time.now
            next_time + (((60 - next_time.min + minute.to_i) % 60) * 60)

          elsif minute =~ /^\d+$/ && hour =~ /^\d+$/
            # Daily at specific time
            target_hour = hour.to_i
            target_minute = minute.to_i

            next_time = Time.now
            next_time = Time.new(next_time.year, next_time.month, next_time.day, target_hour, target_minute, 0)

            # If we've already passed this time today, schedule for tomorrow
            if next_time <= Time.now
              next_time += 86_400 # Add one day
            end

            next_time
          else
            # Unsupported pattern, default to hourly
            (last_run || Time.now) + 3600
          end
        else
          # Invalid cron expression, default to hourly
          Desiru.logger.warn("Invalid cron expression: #{cron_expression}, defaulting to hourly")
          (last_run || Time.now) + 3600
        end
      end
    end

    # Mixin for making jobs schedulable
    module Schedulable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Schedule this job to run periodically
        def schedule(cron:, name: nil, args: [], **)
          job_name = name || self.name
          Scheduler.instance.schedule(job_name,
                                      job_class: self,
                                      cron: cron,
                                      args: args,
                                      **)
        end

        # Remove this job from the schedule
        def unschedule(name: nil)
          job_name = name || self.name
          Scheduler.instance.unschedule(job_name)
        end

        # Check if this job is scheduled
        def scheduled?(name: nil)
          job_name = name || self.name
          Scheduler.instance.job_info(job_name) != nil
        end
      end
    end
  end
end
