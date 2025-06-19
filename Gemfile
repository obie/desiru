# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.2.0'

# Specify your gem's dependencies in desiru.gemspec
gemspec

group :development, :test do
  gem 'mock_redis', '~> 0.40'
  gem 'pry', '~> 0.14'
  gem 'pry-byebug', '~> 3.10'
  gem 'rack-test', '~> 2.0'
  gem 'rake', '~> 13.0'
  gem 'rspec', '~> 3.0'
  gem 'rubocop', '~> 1.21'
  gem 'rubocop-rake', '~> 0.6'
  gem 'rubocop-rspec', '~> 2.0'
  gem 'simplecov', '~> 0.22', require: false
  gem 'webmock', '~> 3.0'
  gem 'yard', '~> 0.9'
end

# LLM interaction dependencies
gem 'faraday', '~> 2.0'
gem 'faraday-retry', '~> 2.0'
gem 'raix', '~> 0.4'

# GraphQL support
gem 'graphql', '~> 2.0'

# REST API support
gem 'grape', '~> 2.0'
gem 'rack-cors', '~> 2.0'
gem 'sinatra', '~> 3.0'
gem 'sinatra-contrib', '~> 3.0'

# Database support
gem 'sequel', '~> 5.0'
gem 'sqlite3', '~> 1.6' # For development/testing

# Optional dependencies for enhanced functionality
group :optional do
  gem 'async', '~> 2.0' # For concurrent operations
  gem 'dry-struct', '~> 1.0' # For type safety
  gem 'dry-validation', '~> 1.0' # For validation
  gem 'jwt', '~> 2.0' # For API authentication
  gem 'rack-throttle', '~> 0.7' # For rate limiting
  gem 'redis', '~> 5.0' # For caching
end
