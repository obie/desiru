# frozen_string_literal: true

require 'test_helper'

class Desiru::ModuleTest < Minitest::Test
  def setup
    # Mock model for testing
    @mock_model = Object.new
    def @mock_model.complete(_prompt)
      { text: 'mocked response' }
    end

    # Configure Desiru with mock model
    Desiru.configure do |config|
      config.default_model = @mock_model
    end

    @simple_module_class = Class.new(Desiru::Module) do
      def forward(text:)
        { result: "processed: #{text}" }
      end
    end
  end

  def test_module_initialization
    instance = @simple_module_class.new('text: string -> result: string')

    assert_instance_of @simple_module_class, instance
    assert_instance_of Desiru::Signature, instance.signature
  end

  def test_module_with_model
    custom_model = Object.new
    def custom_model.complete(_prompt)
      { text: 'custom response' }
    end

    instance = @simple_module_class.new('text: string -> result: string', model: custom_model)

    assert_equal custom_model, instance.model
  end

  def test_module_call_method
    instance = @simple_module_class.new('text: string -> result: string')
    result = instance.call(text: 'hello')

    assert_equal 'processed: hello', result[:result]
  end

  def test_module_validates_required_inputs
    instance = @simple_module_class.new('text: string -> result: string')

    assert_raises(Desiru::ModuleError) do
      instance.call({})
    end
  end

  def test_module_with_multiple_inputs
    multi_module_class = Class.new(Desiru::Module) do
      def forward(a:, b:)
        { sum: a + b }
      end
    end

    instance = multi_module_class.new('a: integer, b: integer -> sum: integer')
    result = instance.call(a: 5, b: 3)

    assert_equal 8, result[:sum]
  end

  def test_module_with_typed_inputs
    typed_module_class = Class.new(Desiru::Module) do
      def forward(count:, active:)
        { result: "count=#{count} (#{count.class}), active=#{active} (#{active.class})" }
      end
    end

    instance = typed_module_class.new('count: int, active: bool -> result: string')
    # Pass already coerced values
    result = instance.call(count: 10, active: true)

    assert_match(/count=10.*Integer.*active=true.*TrueClass/, result[:result])
  end

  def test_module_reset
    instance = @simple_module_class.new('text: string -> result: string')

    # Call the module
    instance.call(text: 'hello')

    # Reset should clear call count
    instance.reset
    assert_equal 0, instance.instance_variable_get(:@call_count)
  end

  def test_module_to_h
    instance = @simple_module_class.new('text: string -> result: string')
    hash = instance.to_h

    assert_kind_of Hash, hash
    assert_includes hash, :class
    assert_includes hash, :signature
    assert_includes hash, :config
  end
end
