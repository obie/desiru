# frozen_string_literal: true

require 'spec_helper'
require 'desiru/jobs/async_predict'

RSpec.describe Desiru::Jobs::AsyncPredict do
  let(:job) { described_class.new }
  let(:job_id) { 'async-123' }
  let(:module_class) { 'Desiru::Predict' }
  let(:signature_str) { 'question -> answer' }
  let(:inputs) { { question: 'What is 2+2?' } }
  let(:options) { { temperature: 0.5 } }
  let(:redis) { instance_double(Redis) }

  before do
    allow(Redis).to receive(:new).and_return(redis)
  end

  describe '#perform' do
    let(:module_instance) { instance_double(Desiru::Predict) }
    let(:result) { Desiru::ModuleResult.new(answer: '4') }

    context 'when execution succeeds' do
      before do
        predict_class = class_double(Desiru::Predict)
        stub_const('Desiru::Predict', predict_class)
        allow(predict_class).to receive(:new)
          .and_return(module_instance)
        allow(module_instance).to receive(:call).with(question: 'What is 2+2?')
                                                .and_return(result)
      end

      it 'executes the module and stores the result' do
        # Allow status updates
        allow(redis).to receive(:setex).with(/desiru:status:/, anything, anything)

        # Expect result storage
        expect(redis).to receive(:setex).at_least(:once) do |key, ttl, json_data|
          next unless key == "desiru:results:#{job_id}" # Skip status updates

          expect(ttl).to eq(3600)
          data = JSON.parse(json_data, symbolize_names: true)
          expect(data[:success]).to be true
          expect(data[:result]).to eq(answer: '4')
        end

        job.perform(job_id, module_class, signature_str, inputs, options)
      end
    end

    context 'when execution fails' do
      let(:error) { StandardError.new('Model error') }

      before do
        predict_class = class_double(Desiru::Predict)
        stub_const('Desiru::Predict', predict_class)
        allow(predict_class).to receive(:new).and_return(module_instance)
        allow(module_instance).to receive(:call).and_raise(error)
      end

      it 'stores the error and re-raises' do
        # Allow status updates
        allow(redis).to receive(:setex).with(/desiru:status:/, anything, anything)

        # Expect error result storage
        expect(redis).to receive(:setex).at_least(:once) do |key, ttl, json_data|
          next unless key == "desiru:results:#{job_id}" # Skip status updates

          expect(ttl).to eq(3600)
          data = JSON.parse(json_data, symbolize_names: true)
          expect(data[:success]).to be false
          expect(data[:error]).to eq('Model error')
          expect(data[:error_class]).to eq('StandardError')
        end

        expect { job.perform(job_id, module_class, signature_str, inputs, options) }
          .to raise_error(StandardError, 'Model error')
      end
    end
  end
end
