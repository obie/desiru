# Job Scheduling in Desiru

Desiru provides a built-in job scheduling system that allows you to run background jobs periodically without adding external dependencies like sidekiq-cron.

## Features

- Simple cron-like scheduling expressions
- Interval-based scheduling ("every 5 minutes")
- Standard cron expressions support
- Lightweight implementation with no external dependencies
- Thread-safe singleton scheduler
- Easy mixin for making jobs schedulable

## Usage

### Making a Job Schedulable

Include the `Schedulable` mixin in your job class:

```ruby
class MyPeriodicJob < Desiru::Jobs::Base
  include Desiru::Jobs::Schedulable

  def perform(job_id = nil)
    # Your job logic here
    puts "Running periodic job: #{job_id}"
    
    # Store result if needed
    store_result(job_id, { status: 'completed', timestamp: Time.now })
  end
end
```

### Scheduling Jobs

#### Simple Interval Scheduling

```ruby
# Run every 60 seconds
MyPeriodicJob.schedule(cron: '60')

# Run every 5 minutes
MyPeriodicJob.schedule(cron: 'every 5 minutes')

# Run every 2 hours
MyPeriodicJob.schedule(cron: 'every 2 hours')

# Run daily
MyPeriodicJob.schedule(cron: 'every 1 day')
```

#### Cron Expression Scheduling

```ruby
# Run every minute
MyPeriodicJob.schedule(cron: '* * * * *')

# Run every hour at minute 0
MyPeriodicJob.schedule(cron: '0 * * * *')

# Run daily at 9:30 AM
MyPeriodicJob.schedule(cron: '30 9 * * *')
```

#### Advanced Scheduling Options

```ruby
# Schedule with custom name
MyPeriodicJob.schedule(
  name: 'custom_job_name',
  cron: 'every 30 minutes'
)

# Schedule with arguments
MyPeriodicJob.schedule(
  cron: 'every 1 hour',
  args: ['arg1', 'arg2']
)

# Schedule with additional options
MyPeriodicJob.schedule(
  name: 'important_job',
  cron: '0 */6 * * *',  # Every 6 hours
  args: ['production'],
  priority: 'high'      # Additional options passed through
)
```

### Managing the Scheduler

```ruby
scheduler = Desiru::Jobs::Scheduler.instance

# Start the scheduler
scheduler.start

# Check if scheduler is running
scheduler.running? # => true

# Stop the scheduler
scheduler.stop

# Get information about a scheduled job
info = scheduler.job_info('MyPeriodicJob')
# => { job_class: MyPeriodicJob, cron: '60', next_run: Time, ... }

# Clear all scheduled jobs
scheduler.clear
```

### Checking Job Status

```ruby
# Check if a job is scheduled
MyPeriodicJob.scheduled? # => true

# Check by custom name
MyPeriodicJob.scheduled?(name: 'custom_job_name') # => true

# Unschedule a job
MyPeriodicJob.unschedule

# Unschedule by name
MyPeriodicJob.unschedule(name: 'custom_job_name')
```

## Supported Cron Formats

### Interval Expressions

- Simple seconds: `"60"` (runs every 60 seconds)
- Natural language: `"every N [second(s)|minute(s)|hour(s)|day(s)]"`

### Cron Expressions

Currently supports basic cron patterns:

- `* * * * *` - Every minute
- `0 * * * *` - Every hour at minute 0
- `30 10 * * *` - Daily at 10:30 AM

More complex cron patterns default to hourly execution.

## Implementation Details

The scheduler:
- Runs in a background thread
- Checks for jobs to run every second
- Generates unique job IDs for each scheduled execution
- Logs job execution and errors
- Handles job execution errors gracefully without stopping the scheduler

## Example

See `examples/scheduled_job_example.rb` for a complete working example of scheduled jobs.

## Best Practices

1. **Idempotent Jobs**: Make your scheduled jobs idempotent since they may run multiple times
2. **Error Handling**: Include proper error handling in your job's perform method
3. **Logging**: Use Desiru.logger for consistent logging
4. **Resource Cleanup**: Stop the scheduler gracefully when shutting down your application
5. **Monitoring**: Monitor scheduled job execution through job results and logs

## Integration with Sidekiq

The scheduler integrates seamlessly with Sidekiq. When a scheduled job's time comes, the scheduler calls `perform_async` on the job class, which enqueues it into Sidekiq for processing.