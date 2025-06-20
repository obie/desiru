# Installation Guide

This guide will help you install and configure Desiru for your Ruby project.

## Prerequisites

- Ruby 3.0 or higher
- Bundler
- Redis (optional, for background processing)
- PostgreSQL, MySQL, or SQLite (optional, for persistence)

## Installation Methods

### Using Bundler (Recommended)

Add Desiru to your `Gemfile`:

```ruby
gem 'desiru'

# Optional dependencies
gem 'redis' # For background processing
gem 'sidekiq' # For job queues
gem 'pg' # For PostgreSQL persistence
gem 'grape' # For REST API
gem 'graphql' # For GraphQL API
```

Then run:

```bash
bundle install
```

### Direct Installation

Install the gem directly:

```bash
gem install desiru
```

## Configuration

### Basic Setup

Create an initializer (e.g., `config/initializers/desiru.rb` for Rails):

```ruby
require 'desiru'

Desiru.configure do |config|
  # Default LLM model
  config.default_model = Desiru::Models::OpenAI.new(
    api_key: ENV['OPENAI_API_KEY'],
    model: 'gpt-4-turbo-preview'
  )
  
  # Optional: Configure caching
  config.cache_store = Rails.cache # For Rails apps
  # Or use built-in memory cache
  config.cache_store = Desiru::Cache::Memory.new
end
```

### Model Configuration

Desiru supports multiple LLM providers through Raix:

```ruby
# OpenAI
openai_model = Desiru::Models::OpenAI.new(
  api_key: ENV['OPENAI_API_KEY'],
  model: 'gpt-4-turbo-preview',
  temperature: 0.7
)

# Anthropic Claude
claude_model = Desiru::Models::Anthropic.new(
  api_key: ENV['ANTHROPIC_API_KEY'],
  model: 'claude-3-opus-20240229'
)

# OpenRouter (access multiple models)
router_model = Desiru::Models::OpenRouter.new(
  api_key: ENV['OPENROUTER_API_KEY'],
  model: 'anthropic/claude-3-opus'
)

# Local models via Ollama
ollama_model = Desiru::Models::Ollama.new(
  base_url: 'http://localhost:11434',
  model: 'llama2:70b'
)
```

### Background Processing Setup

To enable async processing with Sidekiq:

1. Add Redis configuration:

```ruby
Desiru.configure do |config|
  config.redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379'
  config.job_queue = :default
  config.job_retry = 3
end
```

2. Create `config/sidekiq.yml`:

```yaml
:concurrency: 5
:queues:
  - default
  - desiru_low
  - desiru_high
```

3. Start Sidekiq workers:

```bash
bundle exec sidekiq
```

### Database Persistence Setup

To enable persistence features:

```ruby
require 'desiru/persistence'

# Configure database URL
Desiru::Persistence.database_url = ENV['DATABASE_URL'] || 'postgres://localhost/desiru_development'

# Connect and run migrations
Desiru::Persistence.connect!
Desiru::Persistence.migrate!

# Optional: Configure connection pool
Desiru::Persistence.configure_connection do |config|
  config.max_connections = 10
  config.pool_timeout = 5
end
```

For new projects, run the migrations:

```bash
bundle exec rake desiru:db:migrate
```

### Rails Integration

For Rails applications, create `config/initializers/desiru.rb`:

```ruby
Rails.application.config.after_initialize do
  Desiru.configure do |config|
    # Use Rails cache
    config.cache_store = Rails.cache
    
    # Use Rails logger
    config.logger = Rails.logger
    
    # Database persistence
    if defined?(Desiru::Persistence)
      Desiru::Persistence.database_url = ENV['DATABASE_URL']
      Desiru::Persistence.connect!
    end
  end
end
```

## Environment Variables

Recommended environment variables:

```bash
# .env file
OPENAI_API_KEY=your-openai-key
ANTHROPIC_API_KEY=your-anthropic-key
OPENROUTER_API_KEY=your-openrouter-key
REDIS_URL=redis://localhost:6379
DATABASE_URL=postgres://localhost/desiru_development
```

## Verify Installation

Test your installation:

```ruby
require 'desiru'

# Create a simple module
predict = Desiru::Predict.new("question -> answer")

# Test it
result = predict.call(question: "What is 2+2?")
puts result.answer # Should output "4" or similar
```

## Next Steps

- Continue to the [Quick Start Tutorial](Quick-Start)
- Learn about [Core Concepts](Core-Concepts)
- Explore [example applications](Examples)

## Troubleshooting

### Common Issues

**OpenAI API errors**: Ensure your API key is set correctly and has sufficient credits.

**Redis connection errors**: Verify Redis is running: `redis-cli ping`

**Database errors**: Check your database URL and ensure migrations have run.

**Module not found errors**: Ensure you've required the necessary components:
```ruby
require 'desiru/persistence' # For persistence features
require 'desiru/api' # For REST API features
require 'desiru/graphql' # For GraphQL features
```

For more help, see our [FAQ](FAQ) or [open an issue](https://github.com/obie/desiru/issues).