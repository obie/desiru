# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Desiru
  module Jobs
    # Handles webhook notifications for job events
    class WebhookNotifier
      attr_reader :config

      def initialize(config = {})
        @config = {
          timeout: 30,
          retry_count: 3,
          retry_delay: 1,
          headers: {
            'Content-Type' => 'application/json',
            'User-Agent' => "Desiru/#{Desiru::VERSION}"
          }
        }.merge(config)
      end

      # Send a webhook notification
      # @param url [String] the webhook URL
      # @param payload [Hash] the payload to send
      # @param options [Hash] additional options
      # @return [WebhookResult] the result of the webhook call
      def notify(url, payload, options = {})
        uri = URI.parse(url)
        headers = config[:headers].merge(options[:headers] || {})

        # Add signature if secret is provided
        if options[:secret]
          signature = generate_signature(payload, options[:secret])
          headers['X-Desiru-Signature'] = signature
        end

        attempt = 0
        last_error = nil

        while attempt < config[:retry_count]
          attempt += 1

          begin
            response = send_request(uri, payload, headers)

            if response.code.to_i >= 200 && response.code.to_i < 300
              return WebhookResult.new(
                success: true,
                status_code: response.code.to_i,
                body: response.body,
                headers: response.to_hash,
                attempts: attempt
              )
            else
              last_error = "HTTP #{response.code}: #{response.body}"
              Desiru.logger.warn("Webhook failed (attempt #{attempt}/#{config[:retry_count]}): #{last_error}")
            end
          rescue StandardError => e
            last_error = e.message
            Desiru.logger.error("Webhook error (attempt #{attempt}/#{config[:retry_count]}): #{e.message}")
          end

          # Retry with delay if not the last attempt
          if attempt < config[:retry_count]
            sleep(config[:retry_delay] * attempt) # Exponential backoff
          end
        end

        # All attempts failed
        WebhookResult.new(
          success: false,
          error: last_error,
          attempts: attempt
        )
      end

      private

      def send_request(uri, payload, headers)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = config[:timeout]
        http.open_timeout = config[:timeout]

        request = Net::HTTP::Post.new(uri.request_uri)
        headers.each { |key, value| request[key] = value }
        request.body = payload.to_json

        http.request(request)
      end

      def generate_signature(payload, secret)
        require 'openssl'
        digest = OpenSSL::Digest.new('sha256')
        OpenSSL::HMAC.hexdigest(digest, secret, payload.to_json)
      end
    end

    # Result of a webhook notification
    class WebhookResult
      attr_reader :success, :status_code, :body, :headers, :error, :attempts

      def initialize(success:, status_code: nil, body: nil, headers: nil, error: nil, attempts: 1)
        @success = success
        @status_code = status_code
        @body = body
        @headers = headers
        @error = error
        @attempts = attempts
      end

      def success?
        @success
      end

      def failed?
        !@success
      end
    end

    # Configuration for webhook notifications
    class WebhookConfig
      attr_accessor :enabled, :url, :secret, :events, :include_payload, :custom_headers

      def initialize
        @enabled = false
        @url = nil
        @secret = nil
        @events = %i[completed failed] # Which events to notify on
        @include_payload = true # Include job result in webhook
        @custom_headers = {}
      end

      def valid?
        enabled && url && !url.empty?
      end
    end

    # Mixin to add webhook support to jobs
    module Webhookable
      def self.included(base)
        base.extend(ClassMethods)
        base.instance_variable_set(:@webhook_config, WebhookConfig.new)
      end

      def self.prepended(base)
        base.extend(ClassMethods)
        base.instance_variable_set(:@webhook_config, WebhookConfig.new)
      end

      def perform(*args)
        job_id = args.first || "job-#{Time.now.to_i}"
        result = nil
        error = nil
        status = :completed

        begin
          # Call the original perform method
          result = super
        rescue StandardError => e
          error = e
          status = :failed
          raise # Re-raise to maintain normal error handling
        ensure
          # Send webhook notification if configured
          send_webhook_notification(job_id, status, result, error) if should_notify_webhook?(status)
        end

        result
      end

      module ClassMethods
        def webhook_config
          @webhook_config ||= WebhookConfig.new
        end

        def configure_webhook
          yield(webhook_config) if block_given?
        end

        def webhook_enabled?
          webhook_config.valid?
        end
      end

      private

      def should_notify_webhook?(status)
        self.class.webhook_enabled? &&
          self.class.webhook_config.events.include?(status)
      end

      def send_webhook_notification(job_id, status, result, error)
        payload = build_webhook_payload(job_id, status, result, error)

        notifier = WebhookNotifier.new
        webhook_result = notifier.notify(
          self.class.webhook_config.url,
          payload,
          secret: self.class.webhook_config.secret,
          headers: self.class.webhook_config.custom_headers
        )

        if webhook_result.failed?
          Desiru.logger.error("Failed to send webhook for job #{job_id}: #{webhook_result.error}")
        else
          Desiru.logger.info("Webhook notification sent for job #{job_id}")
        end
      rescue StandardError => e
        # Don't let webhook failures affect job execution
        Desiru.logger.error("Webhook notification error: #{e.message}")
      end

      def build_webhook_payload(job_id, status, result, error)
        payload = {
          job_id: job_id,
          job_class: self.class.name,
          status: status.to_s,
          timestamp: Time.now.iso8601,
          environment: ENV['RACK_ENV'] || ENV['RAILS_ENV'] || 'development'
        }

        if self.class.webhook_config.include_payload
          if status == :completed && result
            payload[:result] = result
          elsif status == :failed && error
            payload[:error] = {
              class: error.class.name,
              message: error.message,
              backtrace: error.backtrace&.first(5) # Limit backtrace size
            }
          end
        end

        payload
      end
    end
  end
end
