# frozen_string_literal: true

require 'test_helper'

class Desiru::SignatureTest < Minitest::Test
  def test_simple_signature
    sig = Desiru::Signature.new('question: string -> answer: string')

    # Access input/output fields through the field wrappers
    assert sig.inputs.key?('question')
    assert sig.outputs.key?('answer')
    assert_equal :string, sig.inputs['question'].type
    assert_equal :string, sig.outputs['answer'].type
  end

  def test_multiple_inputs
    sig = Desiru::Signature.new('a: int, b: float -> result: string')

    assert sig.inputs.key?('a')
    assert sig.inputs.key?('b')
    assert sig.outputs.key?('result')
    assert_equal :int, sig.inputs['a'].type
    assert_equal :float, sig.inputs['b'].type
  end

  def test_multiple_outputs
    sig = Desiru::Signature.new('text: string -> summary: string, keywords: list[string]')

    assert sig.inputs.key?('text')
    assert sig.outputs.key?('summary')
    assert sig.outputs.key?('keywords')
    assert_equal :list, sig.outputs['keywords'].type
  end

  def test_signature_with_descriptions
    sig = Desiru::Signature.new(
      'question: string "The question to answer" -> answer: string "The generated answer"'
    )

    assert sig.inputs.key?('question')
    assert sig.outputs.key?('answer')

    # Field descriptions
    assert_equal 'The question to answer', sig.inputs['question'].description
    assert_equal 'The generated answer', sig.outputs['answer'].description
  end

  def test_signature_to_s
    sig = Desiru::Signature.new('question: string -> answer: string')

    # The to_s method should return a normalized representation
    assert_match(/question.*string.*answer.*string/, sig.to_s)
  end

  def test_literal_types
    sig = Desiru::Signature.new('mode: Literal["fast", "slow"] -> result: string')

    assert sig.inputs.key?('mode')
    assert_equal :literal, sig.inputs['mode'].type
  end

  def test_complex_types
    sig = Desiru::Signature.new('data: dict[string, list[float]] -> processed: bool')

    assert sig.inputs.key?('data')
    assert_equal :hash, sig.inputs['data'].type
    assert_equal :bool, sig.outputs['processed'].type
  end

  def test_validate_inputs
    sig = Desiru::Signature.new('text: string, count: int -> result: string')

    # Valid inputs should not raise
    sig.validate_inputs(text: 'hello', count: 5)

    # Missing required input should raise
    assert_raises Desiru::SignatureError do
      sig.validate_inputs(text: 'hello')
    end
  end

  def test_coerce_inputs
    sig = Desiru::Signature.new('count: int, active: bool -> result: string')

    coerced = sig.coerce_inputs(count: '10', active: 'true')
    assert_equal 10, coerced[:count]
    assert_equal true, coerced[:active]
  end
end
