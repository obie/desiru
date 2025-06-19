# frozen_string_literal: true

module Desiru
  module Optimizers
    # Base class for all optimizers
    class Base
      attr_reader :metric, :config

      def initialize(metric: :exact_match, **config)
        @metric = normalize_metric(metric)
        @config = default_config.merge(config)
        @optimization_trace = []
      end

      def compile(program, trainset:, valset: nil)
        raise NotImplementedError, 'Subclasses must implement #compile'
      end

      def optimize_module(module_instance, examples)
        raise NotImplementedError, 'Subclasses must implement #optimize_module'
      end

      def evaluate(program, dataset)
        scores = dataset.map do |example|
          prediction = program.call(example.except(:answer, :output))
          score_prediction(prediction, example)
        end

        {
          average_score: scores.sum.to_f / scores.size,
          scores: scores,
          total: scores.size
        }
      end

      protected

      def default_config
        {
          max_bootstrapped_demos: 3,
          max_labeled_demos: 16,
          max_errors: 5,
          num_candidates: 1,
          stop_at_score: 1.0
        }
      end

      def score_prediction(prediction, ground_truth)
        case @metric
        when Proc
          @metric.call(prediction, ground_truth)
        when :exact_match
          exact_match_score(prediction, ground_truth)
        when :f1
          f1_score(prediction, ground_truth)
        when :accuracy
          accuracy_score(prediction, ground_truth)
        else
          raise OptimizerError, "Unknown metric: #{@metric}"
        end
      end

      def exact_match_score(prediction, ground_truth)
        pred_answer = extract_answer(prediction)
        true_answer = extract_answer(ground_truth)

        pred_answer.to_s.strip.downcase == true_answer.to_s.strip.downcase ? 1.0 : 0.0
      end

      def f1_score(prediction, ground_truth)
        pred_tokens = tokenize(extract_answer(prediction))
        true_tokens = tokenize(extract_answer(ground_truth))

        return 0.0 if pred_tokens.empty? && true_tokens.empty?
        return 0.0 if pred_tokens.empty? || true_tokens.empty?

        precision = (pred_tokens & true_tokens).size.to_f / pred_tokens.size
        recall = (pred_tokens & true_tokens).size.to_f / true_tokens.size

        return 0.0 if (precision + recall).zero?

        2 * (precision * recall) / (precision + recall)
      end

      def accuracy_score(prediction, ground_truth)
        exact_match_score(prediction, ground_truth)
      end

      def extract_answer(data)
        case data
        when ModuleResult, ProgramResult
          # Try common answer fields
          data[:answer] || data[:output] || data[:result] || data.values.first
        when Hash
          data[:answer] || data[:output] || data[:result] || data.values.first
        else
          data
        end
      end

      def tokenize(text)
        text.to_s.downcase.split(/\W+/).reject(&:empty?)
      end

      def normalize_metric(metric)
        case metric
        when Symbol, String
          metric.to_sym
        when Proc
          metric
        else
          raise OptimizerError, 'Metric must be a symbol or proc'
        end
      end

      def trace_optimization(step, details)
        @optimization_trace << {
          step: step,
          timestamp: Time.now,
          details: details
        }

        Desiru.configuration.logger&.info("[Optimizer] #{step}: #{details}")
      end
    end

    # Base error for optimizer-related issues
    class OptimizerError < Error; end
  end
end
