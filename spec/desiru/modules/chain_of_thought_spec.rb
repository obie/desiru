# frozen_string_literal: true

require 'spec_helper'
require 'desiru/modules/chain_of_thought'

RSpec.describe Desiru::Modules::ChainOfThought do
  let(:mock_model) do
    double('Model',
           complete: { content: <<~CNT },
             reasoning: Some reason for this mock answer
             answer: 42
           CNT
           temperature: 0.7,
           respond_to?: true)
  end

  describe '#initialize' do
    context 'with signature string' do
      let(:signature_string) { 'question: string -> answer: string' }
      let(:cot_module) { described_class.new(signature_string, model: mock_model) }

      it 'wraps original_signature with Signature instance' do
        expect(cot_module.original_signature).to respond_to(:output_fields)
        expect(cot_module.original_signature).to be_a(Desiru::Signature)
      end
    end
  end

  describe "#forward" do
    context 'with signature string' do
      let(:signature_string) { 'question: string -> answer: string' }
      let(:cot_module) { described_class.new(signature_string, model: mock_model) }

      it 'can build the prompt and complete a response' do
        result = cot_module.call(question: "Two dice are tossed. What is the probability that the sum equals two?")
        expect(result.answer).to eq "42"
      end
    end
  end
end
