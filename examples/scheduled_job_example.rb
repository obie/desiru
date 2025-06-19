# frozen_string_literal: true

require 'desiru'
require 'desiru/jobs/scheduler'

# Example of a scheduled job that performs periodic tasks
class CleanupJob < Desiru::Jobs::Base
  include Desiru::Jobs::Schedulable

  def perform(job_id = nil)
    # Simulate cleanup work
    puts "[#{Time.now}] Running cleanup job #{job_id}"

    # Example: Clean up old job results
    expired_count = cleanup_expired_results

    # Store the result
    store_result(job_id || "cleanup-#{Time.now.to_i}", {
                   status: 'completed',
                   expired_count: expired_count,
                   timestamp: Time.now.to_s
                 })
  end

  private

  def cleanup_expired_results
    # Simulate cleanup logic
    rand(0..10)
  end
end

# Example of a report generation job
class DailyReportJob < Desiru::Jobs::Base
  include Desiru::Jobs::Schedulable

  def perform(job_id = nil, report_type = 'summary')
    puts "[#{Time.now}] Generating #{report_type} report"

    # Simulate report generation
    report_data = generate_report(report_type)

    store_result(job_id || "report-#{Time.now.to_i}", {
                   status: 'completed',
                   type: report_type,
                   data: report_data,
                   generated_at: Time.now.to_s
                 })
  end

  private

  def generate_report(type)
    # Simulate report generation
    {
      total_jobs: rand(100..1000),
      successful: rand(80..100),
      failed: rand(0..20),
      report_type: type
    }
  end
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  scheduler = Desiru::Jobs::Scheduler.instance

  # Schedule cleanup job to run every 30 seconds
  CleanupJob.schedule(cron: '30')

  # Schedule cleanup with a custom name
  CleanupJob.schedule(name: 'hourly_cleanup', cron: 'every 1 hour')

  # Schedule daily report at 9:00 AM
  DailyReportJob.schedule(
    name: 'morning_report',
    cron: '0 9 * * *',
    args: ['detailed']
  )

  # Schedule summary report every 5 minutes
  DailyReportJob.schedule(
    name: 'summary_report',
    cron: 'every 5 minutes',
    args: ['summary']
  )

  # Check scheduled jobs
  puts "Jobs scheduled:"
  puts "- CleanupJob: #{CleanupJob.scheduled?}"
  puts "- Hourly Cleanup: #{scheduler.job_info('hourly_cleanup') ? 'Yes' : 'No'}"
  puts "- Morning Report: #{scheduler.job_info('morning_report') ? 'Yes' : 'No'}"
  puts "- Summary Report: #{scheduler.job_info('summary_report') ? 'Yes' : 'No'}"

  # Start the scheduler
  puts "\nStarting scheduler..."
  scheduler.start

  # Run for demonstration (in production, this would run continuously)
  puts "Scheduler running. Press Ctrl+C to stop."

  begin
    sleep
  rescue Interrupt
    puts "\nStopping scheduler..."
    scheduler.stop

    # Optionally unschedule jobs
    CleanupJob.unschedule
    CleanupJob.unschedule(name: 'hourly_cleanup')
    DailyReportJob.unschedule(name: 'morning_report')
    DailyReportJob.unschedule(name: 'summary_report')

    puts "Scheduler stopped."
  end
end
