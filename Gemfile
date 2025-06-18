# frozen_string_literal: true

source 'https://rubygems.org'

ruby '~> 3.4.2'

# Specify your gem's dependencies in desiru.gemspec
gemspec

group :development, :test do
  gem 'pry', '~> 0.14'
  gem 'pry-byebug', '~> 3.10'
  gem 'rake', '~> 13.0'
  gem 'rspec', '~> 3.0'
  gem 'rubocop', '~> 1.21'
  gem 'rubocop-rake', '~> 0.6'
  gem 'rubocop-rspec', '~> 2.0'
  gem 'simplecov', '~> 0.22', require: false
  gem 'yard', '~> 0.9'
end

# LLM interaction dependencies
gem 'faraday', '~> 2.0'
gem 'faraday-retry', '~> 2.0'
gem 'raix', '~> 0.4'

# GraphQL support
gem 'graphql', '~> 2.0'

# Optional dependencies for enhanced functionality
group :optional do
  gem 'async', '~> 2.0' # For concurrent operations
  gem 'dry-struct', '~> 1.0' # For type safety
  gem 'dry-validation', '~> 1.0' # For validation
  gem 'redis', '~> 5.0' # For caching
end
