# frozen_string_literal: true

require 'spec_helper'
require 'desiru/jobs/webhook_notifier'
require 'webmock/rspec'

RSpec.describe Desiru::Jobs::WebhookNotifier do
  let(:notifier) { described_class.new }
  let(:webhook_url) { 'https://example.com/webhook' }
  let(:payload) { { job_id: 'test-123', status: 'completed' } }

  describe '#notify' do
    context 'successful webhook' do
      before do
        stub_request(:post, webhook_url)
          .with(
            body: payload.to_json,
            headers: {
              'Content-Type' => 'application/json',
              'User-Agent' => "Desiru/#{Desiru::VERSION}"
            }
          )
          .to_return(status: 200, body: 'OK', headers: { 'X-Request-Id' => '123' })
      end

      it 'sends the webhook and returns success' do
        result = notifier.notify(webhook_url, payload)

        expect(result).to be_success
        expect(result.status_code).to eq(200)
        expect(result.body).to eq('OK')
        expect(result.headers['x-request-id']).to eq(['123'])
        expect(result.attempts).to eq(1)
      end
    end

    context 'with custom headers' do
      it 'includes custom headers in the request' do
        custom_headers = { 'X-Custom-Header' => 'test-value' }

        stub_request(:post, webhook_url)
          .to_return(status: 200)

        notifier.notify(webhook_url, payload, headers: custom_headers)

        expect(WebMock).to(have_requested(:post, webhook_url)
          .with { |req| req.headers['X-Custom-Header'] == 'test-value' })
      end
    end

    context 'with webhook secret' do
      let(:secret) { 'webhook_secret_key' }

      it 'includes HMAC signature in headers' do
        expected_signature = OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new('sha256'),
          secret,
          payload.to_json
        )

        stub_request(:post, webhook_url)
          .to_return(status: 200)

        notifier.notify(webhook_url, payload, secret: secret)

        expect(WebMock).to(have_requested(:post, webhook_url)
          .with { |req| req.headers['X-Desiru-Signature'] == expected_signature })
      end
    end

    context 'failed webhook' do
      before do
        stub_request(:post, webhook_url)
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'retries and returns failure' do
        result = notifier.notify(webhook_url, payload)

        expect(result).to be_failed
        expect(result.error).to include('HTTP 500')
        expect(result.attempts).to eq(3) # Default retry count
        expect(WebMock).to have_requested(:post, webhook_url).times(3)
      end
    end

    context 'network error' do
      before do
        stub_request(:post, webhook_url).to_timeout
      end

      it 'handles network errors and retries' do
        result = notifier.notify(webhook_url, payload)

        expect(result).to be_failed
        expect(result.error).to include('execution expired')
        expect(result.attempts).to eq(3)
      end
    end

    context 'with custom configuration' do
      let(:notifier) do
        described_class.new(
          retry_count: 2,
          retry_delay: 0.1,
          timeout: 5
        )
      end

      before do
        stub_request(:post, webhook_url)
          .to_return(status: 503).times(2)
          .then.to_return(status: 200)
      end

      it 'respects custom retry configuration' do
        result = notifier.notify(webhook_url, payload)

        expect(result).to be_failed
        expect(result.attempts).to eq(2)
        expect(WebMock).to have_requested(:post, webhook_url).times(2)
      end
    end
  end
end

RSpec.describe Desiru::Jobs::WebhookResult do
  context 'successful result' do
    let(:result) do
      described_class.new(
        success: true,
        status_code: 200,
        body: 'OK',
        headers: { 'content-type' => ['application/json'] },
        attempts: 1
      )
    end

    it 'reports success correctly' do
      expect(result).to be_success
      expect(result).not_to be_failed
      expect(result.status_code).to eq(200)
      expect(result.body).to eq('OK')
    end
  end

  context 'failed result' do
    let(:result) do
      described_class.new(
        success: false,
        error: 'Connection refused',
        attempts: 3
      )
    end

    it 'reports failure correctly' do
      expect(result).not_to be_success
      expect(result).to be_failed
      expect(result.error).to eq('Connection refused')
      expect(result.attempts).to eq(3)
    end
  end
end

RSpec.describe Desiru::Jobs::WebhookConfig do
  let(:config) { described_class.new }

  describe 'defaults' do
    it 'has sensible defaults' do
      expect(config.enabled).to be false
      expect(config.url).to be_nil
      expect(config.secret).to be_nil
      expect(config.events).to eq(%i[completed failed])
      expect(config.include_payload).to be true
      expect(config.custom_headers).to eq({})
    end
  end

  describe '#valid?' do
    it 'is invalid without URL' do
      config.enabled = true
      expect(config).not_to be_valid
    end

    it 'is invalid when disabled' do
      config.url = 'https://example.com/webhook'
      expect(config).not_to be_valid
    end

    it 'is valid when enabled with URL' do
      config.enabled = true
      config.url = 'https://example.com/webhook'
      expect(config).to be_valid
    end
  end
end

RSpec.describe Desiru::Jobs::Webhookable do
  let(:job_class) do
    Class.new(Desiru::Jobs::Base) do
      prepend Desiru::Jobs::Webhookable

      def perform(_job_id = nil)
        { result: 'success', processed_at: Time.now.to_s }
      end
    end
  end

  let(:job_instance) { job_class.new }

  describe 'configuration' do
    it 'provides webhook configuration' do
      expect(job_class.webhook_config).to be_a(Desiru::Jobs::WebhookConfig)
    end

    it 'allows webhook configuration' do
      job_class.configure_webhook do |config|
        config.enabled = true
        config.url = 'https://example.com/webhook'
        config.secret = 'test_secret'
        config.events = [:completed]
      end

      expect(job_class.webhook_enabled?).to be true
      expect(job_class.webhook_config.url).to eq('https://example.com/webhook')
      expect(job_class.webhook_config.secret).to eq('test_secret')
      expect(job_class.webhook_config.events).to eq([:completed])
    end
  end

  describe 'webhook notifications' do
    before do
      job_class.configure_webhook do |config|
        config.enabled = true
        config.url = 'https://example.com/job-webhook'
        config.events = %i[completed failed]
      end
    end

    context 'on successful job completion' do
      before do
        stub_request(:post, 'https://example.com/job-webhook')
          .with do |request|
            body = JSON.parse(request.body)
            body['status'] == 'completed' &&
              body['job_class'] == job_class.name &&
              body['result'].is_a?(Hash)
          end
          .to_return(status: 200)
      end

      it 'sends webhook notification' do
        job_instance.perform('test-job-123')

        expect(WebMock).to have_requested(:post, 'https://example.com/job-webhook')
      end
    end

    context 'on job failure' do
      let(:failing_job_class) do
        Class.new(Desiru::Jobs::Base) do
          prepend Desiru::Jobs::Webhookable

          def perform(_job_id = nil)
            raise StandardError, 'Job failed!'
          end
        end
      end

      before do
        failing_job_class.configure_webhook do |config|
          config.enabled = true
          config.url = 'https://example.com/job-webhook'
        end

        stub_request(:post, 'https://example.com/job-webhook')
          .with do |request|
            body = JSON.parse(request.body)
            body['status'] == 'failed' &&
              body['error']['message'] == 'Job failed!'
          end
          .to_return(status: 200)
      end

      it 'sends webhook notification with error details' do
        expect { failing_job_class.new.perform('test-job-123') }.to raise_error(StandardError)

        expect(WebMock).to have_requested(:post, 'https://example.com/job-webhook')
      end
    end

    context 'when webhook notification fails' do
      before do
        stub_request(:post, 'https://example.com/job-webhook')
          .to_return(status: 500)

        allow(Desiru.logger).to receive(:error)
      end

      it 'does not affect job execution' do
        result = job_instance.perform('test-job-123')

        expect(result).to eq({ result: 'success', processed_at: result[:processed_at] })
        expect(Desiru.logger).to have_received(:error).with(/Failed to send webhook/)
      end
    end

    context 'with event filtering' do
      before do
        job_class.configure_webhook do |config|
          config.enabled = true
          config.url = 'https://example.com/job-webhook'
          config.events = [:failed] # Only notify on failures
        end
      end

      it 'does not send webhook for non-configured events' do
        job_instance.perform('test-job-123')

        expect(WebMock).not_to have_requested(:post, 'https://example.com/job-webhook')
      end
    end

    context 'without payload' do
      before do
        job_class.configure_webhook do |config|
          config.enabled = true
          config.url = 'https://example.com/job-webhook'
          config.include_payload = false
        end

        stub_request(:post, 'https://example.com/job-webhook')
          .with do |request|
            body = JSON.parse(request.body)
            !body.key?('result') && !body.key?('error')
          end
          .to_return(status: 200)
      end

      it 'excludes job result from webhook payload' do
        job_instance.perform('test-job-123')

        expect(WebMock).to have_requested(:post, 'https://example.com/job-webhook')
      end
    end
  end
end
