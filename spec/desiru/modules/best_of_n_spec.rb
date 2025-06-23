# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe Desiru::Modules::BestOfN do
  let(:model) { double('model') }
  let(:signature) { Desiru::Signature.new('question: string -> answer: string') }
  let(:module_instance) { described_class.new(signature, model: model) }

  describe '#initialize' do
    it 'sets default values' do
      expect(module_instance.instance_variable_get(:@n_samples)).to eq(5)
      expect(module_instance.instance_variable_get(:@selection_criterion)).to eq(:consistency)
      expect(module_instance.instance_variable_get(:@temperature)).to eq(0.7)
      expect(module_instance.instance_variable_get(:@base_module)).to eq(Desiru::Modules::Predict)
    end

    it 'accepts custom configuration' do
      custom_selector = ->(samples) { samples.first }
      custom_module = described_class.new(
        signature,
        model: model,
        n_samples: 10,
        selection_criterion: :confidence,
        temperature: 0.9,
        custom_selector: custom_selector,
        include_metadata: true
      )

      expect(custom_module.instance_variable_get(:@n_samples)).to eq(10)
      expect(custom_module.instance_variable_get(:@selection_criterion)).to eq(:confidence)
      expect(custom_module.instance_variable_get(:@temperature)).to eq(0.9)
      expect(custom_module.instance_variable_get(:@custom_selector)).to eq(custom_selector)
      expect(custom_module.instance_variable_get(:@include_metadata)).to be true
    end

    it 'raises error for invalid selection criterion' do
      expect do
        described_class.new(signature, model: model, selection_criterion: :invalid)
      end.to raise_error(ArgumentError, /Invalid selection criterion/)
    end
  end

  describe '#forward' do
    let(:inputs) { { question: 'What is the capital of France?' } }
    let(:base_module) { double('base_module') }

    before do
      allow(Desiru::Modules::Predict).to receive(:new).and_return(base_module)
    end

    context 'with consistency criterion' do
      let(:samples) do
        [
          { answer: 'Paris' },
          { answer: 'Paris' },
          { answer: 'Paris' },
          { answer: 'London' },
          { answer: 'Paris' }
        ]
      end

      before do
        allow(base_module).to receive(:forward).and_return(*samples)
      end

      it 'selects the most consistent answer' do
        result = module_instance.forward(**inputs)
        expect(result[:answer]).to eq('Paris')
      end

      it 'generates N samples' do
        expect(base_module).to receive(:forward).exactly(5).times
        module_instance.forward(**inputs)
      end
    end

    context 'with confidence criterion' do
      let(:confidence_module) do
        described_class.new(signature, model: model, selection_criterion: :confidence, n_samples: 3)
      end

      let(:samples) do
        [
          { answer: 'Paris' },
          { answer: 'Lyon' },
          { answer: 'Marseille' }
        ]
      end

      let(:confidence_responses) do
        [
          { content: '85', metadata: {} },
          { content: '60', metadata: {} },
          { content: '70', metadata: {} }
        ]
      end

      before do
        allow(base_module).to receive(:forward).and_return(*samples.take(3))

        # Mock confidence rating calls
        confidence_index = 0
        allow(model).to receive(:complete) do |args|
          if args && args[:messages] && args[:messages][0] && args[:messages][0][:content].include?('Rate the confidence')
            response = confidence_responses[confidence_index]
            confidence_index += 1
            response
          else
            # Return a default response for any other calls
            { content: 'default response', metadata: {} }
          end
        end
      end

      it 'selects the answer with highest confidence' do
        result = confidence_module.forward(**inputs)
        expect(result[:answer]).to eq('Paris') # 85% confidence
      end

      it 'uses low temperature for confidence rating' do
        confidence_module.forward(**inputs)

        expect(model).to have_received(:complete).with(
          hash_including(temperature: 0.1)
        ).at_least(:once)
      end
    end

    context 'with llm_judge criterion' do
      let(:judge_module) do
        described_class.new(signature, model: model, selection_criterion: :llm_judge)
      end

      let(:samples) do
        [
          { answer: 'Paris' },
          { answer: 'Paris, the capital of France' },
          { answer: 'The capital is Paris' }
        ]
      end

      let(:judge_response) do
        {
          content: 'I select Option 2 as it provides the most complete answer.',
          metadata: {}
        }
      end

      before do
        allow(base_module).to receive(:forward).and_return(*samples)
        allow(model).to receive(:complete).and_return(judge_response)
      end

      it 'uses LLM to select the best answer' do
        result = judge_module.forward(**inputs)
        expect(result[:answer]).to eq('Paris, the capital of France')
      end

      it 'includes all samples in the judge prompt' do
        judge_module.forward(**inputs)

        expect(model).to have_received(:complete) do |args|
          prompt = args[:messages][0][:content]
          expect(prompt).to include('Option 1')
          expect(prompt).to include('Option 2')
          expect(prompt).to include('Option 3')
          expect(prompt).to include('Paris')
        end
      end
    end

    context 'with custom criterion' do
      let(:custom_selector) do
        ->(samples) { samples.max_by { |s| s[:answer].length } }
      end

      let(:custom_module) do
        described_class.new(
          signature,
          model: model,
          selection_criterion: :custom,
          custom_selector: custom_selector
        )
      end

      let(:samples) do
        [
          { answer: 'Paris' },
          { answer: 'The beautiful city of Paris' },
          { answer: 'It is Paris' }
        ]
      end

      before do
        allow(base_module).to receive(:forward).and_return(*samples)
      end

      it 'uses custom selector function' do
        result = custom_module.forward(**inputs)
        expect(result[:answer]).to eq('The beautiful city of Paris')
      end

      it 'raises error if custom selector not provided' do
        no_selector_module = described_class.new(
          signature,
          model: model,
          selection_criterion: :custom
        )

        allow(base_module).to receive(:forward).and_return(samples.first)

        expect do
          no_selector_module.forward(**inputs)
        end.to raise_error(ArgumentError, /Custom selector must be provided/)
      end
    end

    context 'with metadata inclusion' do
      let(:metadata_signature) do
        Desiru::Signature.new('question: string -> answer: string, selection_metadata: hash')
      end

      let(:metadata_module) do
        described_class.new(metadata_signature, model: model)
      end

      let(:samples) do
        [
          { answer: 'Paris' },
          { answer: 'Paris' },
          { answer: 'London' },
          { answer: 'Paris' },
          { answer: 'Berlin' }
        ]
      end

      before do
        allow(base_module).to receive(:forward).and_return(*samples)
      end

      it 'includes selection metadata when in signature' do
        result = metadata_module.forward(**inputs)

        expect(result[:selection_metadata]).to be_a(Hash)
        expect(result[:selection_metadata][:total_samples]).to eq(5)
        expect(result[:selection_metadata][:selection_criterion]).to eq(:consistency)
        expect(result[:selection_metadata][:temperature]).to eq(0.7)
        expect(result[:selection_metadata][:agreement_rate]).to eq(0.6) # 3/5 say Paris
      end

      it 'includes metadata when explicitly requested' do
        explicit_module = described_class.new(
          signature,
          model: model,
          include_metadata: true
        )

        allow(base_module).to receive(:forward).and_return(*samples)

        result = explicit_module.forward(**inputs)
        expect(result[:selection_metadata]).to be_a(Hash)
      end
    end

    context 'with different base modules' do
      let(:chain_of_thought) { double('chain_of_thought_module') }

      let(:cot_module) do
        described_class.new(
          signature,
          model: model,
          base_module: chain_of_thought
        )
      end

      let(:samples) do
        [
          { answer: 'Paris', reasoning: 'France is in Europe...' },
          { answer: 'Paris', reasoning: 'The capital of France...' },
          { answer: 'Paris', reasoning: 'Known for the Eiffel Tower...' }
        ]
      end

      before do
        allow(chain_of_thought).to receive(:forward).and_return(*samples)
      end

      it 'uses custom base module for generation' do
        result = cot_module.forward(**inputs)

        expect(chain_of_thought).to have_received(:forward).exactly(5).times
        expect(result[:answer]).to eq('Paris')
        expect(result[:reasoning]).to be_a(String)
      end
    end

    context 'error handling' do
      before do
        allow(Desiru.logger).to receive(:error)
      end

      it 'falls back to single sample on error' do
        # First mock returns base_module that will fail
        # Second mock returns fallback_module that will succeed
        call_count = 0
        allow(Desiru::Modules::Predict).to receive(:new) do
          call_count += 1
          if call_count == 1
            # First instantiation for generate_samples - return module that fails
            base_module
          else
            # Second instantiation for fallback_sample - return module that succeeds
            fallback_module = double('fallback_module')
            allow(fallback_module).to receive(:forward).and_return({ answer: 'Paris' })
            fallback_module
          end
        end

        # Mock the base_module to raise error during sample generation
        allow(base_module).to receive(:forward).and_raise(StandardError, 'Generation failed')

        result = module_instance.forward(**inputs)
        expect(result[:answer]).to eq('Paris')
        expect(Desiru.logger).to have_received(:error).with(/BestOfN error/)
      end
    end

    context 'normalization logic' do
      let(:samples) do
        [
          { answer: 'PARIS' },
          { answer: 'paris' },
          { answer: 'Paris.' },
          { answer: 'Paris!' },
          { answer: 'London' }
        ]
      end

      before do
        allow(base_module).to receive(:forward).and_return(*samples)
      end

      it 'normalizes outputs for consistency comparison' do
        result = module_instance.forward(**inputs)
        # All Paris variants should be treated as the same
        expect(result[:answer]).to match(/paris/i)
      end
    end

    context 'with numeric outputs' do
      let(:numeric_signature) { Desiru::Signature.new('x: int, y: int -> result: float') }
      let(:numeric_module) { described_class.new(numeric_signature, model: model) }
      let(:numeric_inputs) { { x: 5, y: 3 } }

      let(:samples) do
        [
          { result: 1.666 },
          { result: 1.667 },
          { result: 1.67 },
          { result: 2.0 },
          { result: 1.66 }
        ]
      end

      before do
        allow(base_module).to receive(:forward).and_return(*samples)
      end

      it 'handles numeric consistency with rounding' do
        result = numeric_module.forward(**numeric_inputs)
        # Should select one of the ~1.67 values (most common when rounded)
        expect(result[:result]).to be_between(1.66, 1.67)
      end
    end
  end

  describe 'integration with Desiru infrastructure' do
    it 'works with demos' do
      module_with_demos = described_class.new(
        signature,
        model: model,
        demos: [
          { question: 'What is 2+2?', answer: '4' }
        ]
      )

      expect(module_with_demos.demos).not_to be_empty
    end

    it 'supports async execution' do
      expect(described_class.ancestors).to include(Desiru::AsyncCapable)
    end

    it 'integrates with trace collection' do
      base_module = double('base_module')
      allow(Desiru::Modules::Predict).to receive(:new).and_return(base_module)
      allow(base_module).to receive(:forward).and_return({ answer: 'test' })

      expect do
        if defined?(Desiru::TraceContext)
          Desiru::TraceContext.start(:test) do
            module_instance.forward(question: 'test')
          end
        else
          module_instance.forward(question: 'test')
        end
      end.not_to raise_error
    end
  end
end
