# Desiru Examples

This directory contains example scripts demonstrating various features of Desiru.

## Running the Examples

Before running any examples, make sure you have:

1. Installed the gem dependencies:
   ```bash
   bundle install
   ```

2. Set your OpenAI API key:
   ```bash
   export OPENAI_API_KEY="your-api-key-here"
   ```

## Available Examples

### simple_qa.rb
Basic question-answering using the Predict and ChainOfThought modules.

```bash
ruby examples/simple_qa.rb
```

### typed_signatures.rb
Demonstrates typed signatures with input/output validation and field descriptions.

```bash
ruby examples/typed_signatures.rb
```

### few_shot_learning.rb
Shows how to use the BootstrapFewShot optimizer to improve module performance with training examples.

```bash
ruby examples/few_shot_learning.rb
```

### rest_api.rb
Creates a REST API server using Grape integration, exposing Desiru modules as HTTP endpoints.

```bash
ruby examples/rest_api.rb
# Visit http://localhost:9292 for API documentation
```

### rest_api_advanced.rb
Advanced REST API with authentication, rate limiting, and tool-using AI agents.

```bash
ruby examples/rest_api_advanced.rb
# API keys: demo-key-123, test-key-456
```

### sinatra_api.rb
Lightweight REST API using Sinatra integration as an alternative to Grape.

```bash
ruby examples/sinatra_api.rb
# Visit http://localhost:9293 for simpler API endpoints
```

### graphql_integration.rb
GraphQL API server with automatic schema generation from Desiru signatures.

```bash
ruby examples/graphql_integration.rb
# GraphiQL interface at http://localhost:9292/graphiql
```

### react_agent.rb
Demonstrates the ReAct module for building tool-using AI agents.

```bash
ruby examples/react_agent.rb
```

### async_processing.rb
Shows how to use background job processing with Sidekiq for long-running operations.

```bash
# Start Redis first
redis-server

# In another terminal, start Sidekiq workers
bundle exec sidekiq

# Run the example
ruby examples/async_processing.rb
```

### persistence_example.rb
Demonstrates Sequel-based persistence for tracking module executions, API requests, and training data.

```bash
ruby examples/persistence_example.rb
# Creates a SQLite database with execution history
```

### api_with_persistence.rb
REST API server with automatic request tracking and analytics dashboard.

```bash
ruby examples/api_with_persistence.rb
# Visit http://localhost:9294 for the dashboard
```

## Creating Your Own Examples

When creating new examples:

1. Use `require "bundler/setup"` to ensure proper gem loading
2. Configure Desiru with your preferred model
3. Create modules with appropriate signatures
4. Handle API keys securely (use environment variables)

## Notes

- These examples use OpenAI by default, but you can configure other providers (Anthropic, OpenRouter, etc.)
- Make sure to handle API rate limits appropriately in production code
- Consider caching results for expensive operations