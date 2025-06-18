# frozen_string_literal: true

require_relative 'lib/desiru/version'

Gem::Specification.new do |spec|
  spec.name = 'desiru'
  spec.version = Desiru::VERSION
  spec.authors = ['Obie Fernandez']
  spec.email = ['obiefernandez@gmail.com']

  spec.summary = 'Declarative Self-Improving Ruby - A Ruby port of DSPy'
  spec.description = "Desiru brings DSPy's declarative programming paradigm for language models to Ruby, " \
                     'enabling reliable, maintainable, and portable AI programming.'
  spec.homepage = 'https://github.com/obie/desiru'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4.2'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/obie/desiru'
  spec.metadata['changelog_uri'] = 'https://github.com/obie/desiru/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|circleci)|appveyor)})
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'forwardable', '~> 1.3'
  spec.add_dependency 'redis', '~> 5.0'
  spec.add_dependency 'sidekiq', '~> 7.2'
  spec.add_dependency 'singleton', '~> 0.1'

  # Development dependencies (basic ones, others in Gemfile)
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata['rubygems_mfa_required'] = 'true'
end
