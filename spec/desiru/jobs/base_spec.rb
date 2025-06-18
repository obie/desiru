# frozen_string_literal: true

require 'spec_helper'
require 'desiru/jobs/base'

RSpec.describe Desiru::Jobs::Base do
  let(:job) { described_class.new }
  let(:redis) { instance_double(Redis) }

  before do
    allow(Redis).to receive(:new).and_return(redis)
  end

  describe '#perform' do
    it 'raises NotImplementedError' do
      expect { job.perform }.to raise_error(NotImplementedError, /must implement #perform/)
    end
  end

  describe '#store_result' do
    let(:job_id) { 'test-job-123' }
    let(:result) { { status: 'complete', data: 'test' } }

    it 'stores the result in Redis with default TTL' do
      expect(redis).to receive(:setex).with(
        "desiru:results:#{job_id}",
        3600,
        result.to_json
      )

      job.send(:store_result, job_id, result)
    end

    it 'stores the result with custom TTL' do
      custom_ttl = 7200
      expect(redis).to receive(:setex).with(
        "desiru:results:#{job_id}",
        custom_ttl,
        result.to_json
      )

      job.send(:store_result, job_id, result, ttl: custom_ttl)
    end
  end

  describe '#fetch_result' do
    let(:job_id) { 'test-job-123' }
    let(:stored_result) { { status: 'complete', data: 'test' } }

    context 'when result exists' do
      before do
        allow(redis).to receive(:get).with("desiru:results:#{job_id}")
                                     .and_return(stored_result.to_json)
      end

      it 'returns the parsed result' do
        result = job.send(:fetch_result, job_id)
        expect(result).to eq(status: 'complete', data: 'test')
      end
    end

    context 'when result does not exist' do
      before do
        allow(redis).to receive(:get).with("desiru:results:#{job_id}")
                                     .and_return(nil)
      end

      it 'returns nil' do
        result = job.send(:fetch_result, job_id)
        expect(result).to be_nil
      end
    end
  end

  describe '#result_key' do
    it 'returns the correct Redis key format' do
      job_id = 'test-123'
      expect(job.send(:result_key, job_id)).to eq("desiru:results:test-123")
    end
  end
end
