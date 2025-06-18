# frozen_string_literal: true

require 'spec_helper'
require 'desiru/jobs/batch_processor'

RSpec.describe Desiru::Jobs::BatchProcessor do
  let(:job) { described_class.new }
  let(:batch_id) { 'batch-456' }
  let(:module_class) { 'Desiru::Predict' }
  let(:signature_str) { 'question -> answer' }
  let(:inputs_array) do
    [
      { question: 'What is 2+2?' },
      { question: 'What is the capital of France?' },
      { question: 'Invalid question' }
    ]
  end
  let(:options) { { temperature: 0.7 } }
  let(:redis) { instance_double(Redis) }

  before do
    allow(Redis).to receive(:new).and_return(redis)
  end

  describe '#perform' do
    let(:module_instance) { instance_double(Desiru::Predict) }
    let(:result1) { Desiru::ModuleResult.new(answer: '4') }
    let(:result2) { Desiru::ModuleResult.new(answer: 'Paris') }

    before do
      predict_class = class_double(Desiru::Predict)
      stub_const('Desiru::Predict', predict_class)
      allow(predict_class).to receive(:new)
        .and_return(module_instance)
    end

    context 'when all requests succeed' do
      before do
        allow(module_instance).to receive(:call)
          .with(question: 'What is 2+2?')
          .and_return(result1)
        allow(module_instance).to receive(:call)
          .with(question: 'What is the capital of France?')
          .and_return(result2)
        allow(module_instance).to receive(:call)
          .with(question: 'Invalid question')
          .and_return(Desiru::ModuleResult.new(answer: 'Unknown'))
      end

      it 'processes all inputs and stores results' do
        # Allow status updates
        allow(redis).to receive(:setex).with(/desiru:status:/, anything, anything)

        # Expect result storage
        expect(redis).to receive(:setex).at_least(:once) do |key, ttl, json_data|
          next unless key == "desiru:results:#{batch_id}" # Skip status updates

          expect(ttl).to eq(7200)
          data = JSON.parse(json_data, symbolize_names: true)
          expect(data[:success]).to be true
          expect(data[:total]).to eq(3)
          expect(data[:successful]).to eq(3)
          expect(data[:failed]).to eq(0)
        end

        job.perform(batch_id, module_class, signature_str, inputs_array, options)
      end
    end

    context 'when some requests fail' do
      before do
        allow(module_instance).to receive(:call)
          .with(question: 'What is 2+2?')
          .and_return(result1)
        allow(module_instance).to receive(:call)
          .with(question: 'What is the capital of France?')
          .and_return(result2)
        allow(module_instance).to receive(:call)
          .with(question: 'Invalid question')
          .and_raise(StandardError.new('Processing error'))
      end

      it 'processes successful inputs and records errors' do
        stored_data = nil
        allow(redis).to receive(:setex) do |key, _ttl, data|
          stored_data = JSON.parse(data, symbolize_names: true) if key == "desiru:results:#{batch_id}"
        end

        job.perform(batch_id, module_class, signature_str, inputs_array, options)

        expect(stored_data[:success]).to be false
        expect(stored_data[:total]).to eq 3
        expect(stored_data[:successful]).to eq 2
        expect(stored_data[:failed]).to eq 1
        expect(stored_data[:results].size).to eq 2
        expect(stored_data[:errors].size).to eq 1
        expect(stored_data[:errors].first[:error]).to eq 'Processing error'
      end
    end
  end
end
