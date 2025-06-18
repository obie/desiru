# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rake/testtask'

# RSpec task
RSpec::Core::RakeTask.new(:spec)

# Minitest task
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

# Run both RSpec and Minitest
desc 'Run all tests (RSpec and Minitest)'
task tests: %i[spec test]

require 'rubocop/rake_task'

RuboCop::RakeTask.new(:rubocop_ci)

task ci: %i[spec test rubocop_ci]

RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ['--autocorrect']
end

task default: %i[spec rubocop]
