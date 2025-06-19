# frozen_string_literal: true

require 'singleton'

module Desiru
  # Module registry for managing and discovering Desiru modules
  # Implements service locator pattern for module management
  class Registry
    include Singleton

    def initialize
      @modules = {}
      @module_versions = Hash.new { |h, k| h[k] = {} }
      @module_metadata = {}
    end

    def register(name, klass, version: '1.0.0', metadata: {})
      validate_module!(klass)

      name = name.to_sym
      @modules[name] = klass
      @module_versions[name][version] = klass
      @module_metadata[name] = metadata.merge(
        registered_at: Time.now,
        version: version,
        class: klass.name
      )

      Desiru.configuration.logger&.info("Registered module: #{name} v#{version}")
    end

    def get(name, version: nil)
      name = name.to_sym

      return @module_versions[name][version] || raise(ModuleError, "Module #{name} v#{version} not found") if version

      @modules[name] || raise(ModuleError, "Module #{name} not found")
    end

    def list
      @modules.keys
    end

    def metadata(name)
      @module_metadata[name.to_sym]
    end

    def unregister(name)
      name = name.to_sym
      @modules.delete(name)
      @module_versions.delete(name)
      @module_metadata.delete(name)
    end

    def clear!
      @modules.clear
      @module_versions.clear
      @module_metadata.clear
    end

    private

    def validate_module!(klass)
      raise ModuleError, 'Module must be a class' unless klass.respond_to?(:new)

      # Check if it's a Desiru module
      return if klass.ancestors.include?(Desiru::Module)

      raise ModuleError, 'Module must inherit from Desiru::Module'
    end
  end
end
