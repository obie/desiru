# frozen_string_literal: true

require 'test_helper'

# Basic tests to demonstrate Minitest is working correctly
class Desiru::BasicTest < Minitest::Test
  def test_desiru_module_exists
    assert defined?(Desiru)
    assert defined?(Desiru::Module)
  end

  def test_configuration_works
    original_config = Desiru.configuration

    Desiru.configure do |config|
      config.retry_count = 5
    end

    assert_equal 5, Desiru.configuration.retry_count
  ensure
    Desiru.configuration = original_config
  end

  def test_signature_creation
    sig = Desiru::Signature.new('input: string -> output: string')

    assert_instance_of Desiru::Signature, sig
    assert sig.inputs.key?('input')
    assert sig.outputs.key?('output')
  end

  def test_module_creation_with_mock
    mock_model = create_mock_model

    test_module = Class.new(Desiru::Module) do
      def forward(text:)
        { result: text.upcase }
      end
    end

    instance = test_module.new('text: string -> result: string', model: mock_model)
    result = instance.call(text: 'hello')

    assert_equal 'HELLO', result[:result]
  end

  def test_minitest_assertions_work
    # Test various Minitest assertions
    assert true
    assert_equal 2, 1 + 1
    assert_nil nil
    refute_nil 'not nil'
    assert_kind_of String, 'test'
    assert_includes [1, 2, 3], 2
    assert_match(/test/, 'testing')
  end
end
