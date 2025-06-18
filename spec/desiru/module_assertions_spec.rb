# frozen_string_literal: true

require 'spec_helper'
require 'desiru'

RSpec.describe 'Module with Assertions' do
  # Test module that uses assertions
  class TestAssertionModule < Desiru::Module
    def forward(input:, confidence: nil)
      result = { output: "Processed: #{input}", confidence: confidence || 0.5 }
      
      # Use assertion to enforce confidence threshold
      Desiru.assert(result[:confidence] > 0.7, "Confidence too low: #{result[:confidence]}")
      
      result
    end
  end

  # Test module that uses suggestions
  class TestSuggestionModule < Desiru::Module
    def forward(input:, sources: nil)
      result = { output: "Processed: #{input}", sources: sources || [] }
      
      # Use suggestion for optional validation
      Desiru.suggest(result[:sources].any?, "No sources provided")
      
      result
    end
  end

  let(:model) { instance_double('Model', complete: { text: 'response' }) }
  let(:logger) { instance_double(Logger, warn: nil, error: nil) }
  
  before do
    allow(Desiru.configuration).to receive(:logger).and_return(logger)
    Desiru::Assertions.configuration.max_assertion_retries = 3
    Desiru::Assertions.configuration.assertion_retry_delay = 0.01
  end

  describe 'assertion behavior in modules' do
    let(:signature) { Desiru::Signature.new('input:str, confidence:float -> output:str, confidence:float') }
    let(:module_instance) { TestAssertionModule.new(signature, model: model) }

    context 'when assertion passes' do
      it 'returns the result normally' do
        result = module_instance.call(input: 'test', confidence: 0.8)
        expect(result.output).to eq('Processed: test')
        expect(result[:confidence]).to eq(0.8)
      end
    end

    context 'when assertion fails' do
      it 'retries the specified number of times' do
        expect(module_instance).to receive(:forward).exactly(4).times.and_call_original
        
        expect do
          module_instance.call(input: 'test', confidence: 0.5)
        end.to raise_error(Desiru::Assertions::AssertionError, 'Confidence too low: 0.5')
      end

      it 'logs retry attempts' do
        expect(logger).to receive(:warn).with(/\[ASSERTION RETRY\]/).exactly(3).times
        expect(logger).to receive(:error).with(/\[ASSERTION FAILED\]/).once
        
        expect do
          module_instance.call(input: 'test', confidence: 0.5)
        end.to raise_error(Desiru::Assertions::AssertionError)
      end

      it 'includes module context in the error' do
        begin
          module_instance.call(input: 'test', confidence: 0.5)
        rescue Desiru::Assertions::AssertionError => e
          expect(e.module_name).to eq('TestAssertionModule')
          expect(e.retry_count).to eq(3)
        end
      end
    end

    context 'when retry_on_failure is disabled' do
      let(:module_instance) do
        TestAssertionModule.new(signature, model: model, config: { retry_on_failure: false })
      end

      it 'does not retry on assertion failure' do
        expect(module_instance).to receive(:forward).once.and_call_original
        
        expect do
          module_instance.call(input: 'test', confidence: 0.5)
        end.to raise_error(Desiru::Assertions::AssertionError)
      end
    end
  end

  describe 'suggestion behavior in modules' do
    let(:signature) { Desiru::Signature.new('input:str, sources:list[str] -> output:str, sources:list[str]') }
    let(:module_instance) { TestSuggestionModule.new(signature, model: model) }

    context 'when suggestion passes' do
      it 'returns the result without logging' do
        expect(logger).not_to receive(:warn)
        
        result = module_instance.call(input: 'test', sources: ['source1'])
        expect(result.output).to eq('Processed: test')
        expect(result[:sources]).to eq(['source1'])
      end
    end

    context 'when suggestion fails' do
      it 'logs a warning but continues execution' do
        expect(logger).to receive(:warn).with('[SUGGESTION] No sources provided')
        
        result = module_instance.call(input: 'test', sources: [])
        expect(result.output).to eq('Processed: test')
        expect(result[:sources]).to eq([])
      end

      it 'does not trigger retries' do
        expect(module_instance).to receive(:forward).once.and_call_original
        
        module_instance.call(input: 'test', sources: [])
      end
    end
  end

  describe 'mixed assertions and suggestions' do
    class MixedValidationModule < Desiru::Module
      def forward(input:, confidence: nil, sources: nil)
        result = {
          output: "Processed: #{input}",
          confidence: confidence || 0.5,
          sources: sources || []
        }
        
        # Hard assertion
        Desiru.assert(result[:confidence] > 0.7, "Confidence too low")
        
        # Soft suggestion
        Desiru.suggest(result[:sources].any?, "Consider adding sources")
        
        result
      end
    end

    let(:signature) { Desiru::Signature.new('input:str, confidence:float, sources:list[str] -> output:str, confidence:float, sources:list[str]') }
    let(:module_instance) { MixedValidationModule.new(signature, model: model) }

    it 'handles both assertions and suggestions correctly' do
      expect(logger).to receive(:warn).with('[SUGGESTION] Consider adding sources')
      
      result = module_instance.call(input: 'test', confidence: 0.8, sources: [])
      expect(result.output).to eq('Processed: test')
    end

    it 'fails on assertion even if suggestion passes' do
      expect do
        module_instance.call(input: 'test', confidence: 0.5, sources: ['source1'])
      end.to raise_error(Desiru::Assertions::AssertionError, 'Confidence too low')
    end
  end

  describe 'assertion configuration' do
    it 'respects custom retry configuration' do
      Desiru::Assertions.configure do |config|
        config.max_assertion_retries = 2
        config.assertion_retry_delay = 0.001
      end

      signature = Desiru::Signature.new('input:str, confidence:float -> output:str, confidence:float')
      module_instance = TestAssertionModule.new(signature, model: model)
      
      # Should retry only 2 times (3 total attempts)
      expect(module_instance).to receive(:forward).exactly(3).times.and_call_original
      
      expect do
        module_instance.call(input: 'test', confidence: 0.5)
      end.to raise_error(Desiru::Assertions::AssertionError)
    end
  end
end