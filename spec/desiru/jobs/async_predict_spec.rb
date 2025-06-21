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
  let(:redis) { job.send(:redis) }

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
        job.perform(job_id, module_class, signature_str, inputs, options)
        
        stored_value = redis.get("desiru:results:#{job_id}")
        expect(stored_value).not_to be_nil
        data = JSON.parse(stored_value, symbolize_names: true)
        expect(data[:success]).to be true
        expect(data[:result]).to eq(answer: '4')
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
        expect { job.perform(job_id, module_class, signature_str, inputs, options) }
          .to raise_error(StandardError, 'Model error')
          
        stored_value = redis.get("desiru:results:#{job_id}")
        expect(stored_value).not_to be_nil
        data = JSON.parse(stored_value, symbolize_names: true)
        expect(data[:success]).to be false
        expect(data[:error]).to eq('Model error')
        expect(data[:error_class]).to eq('StandardError')
      end
    end
  end
end
