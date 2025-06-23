# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe Desiru::Modules::MultiChainComparison do
  let(:model) { double('model') }
  let(:signature) { Desiru::Signature.new('question: string -> answer: string') }
  let(:module_instance) { described_class.new(signature, model: model) }

  describe '#initialize' do
    it 'sets default values' do
      expect(module_instance.instance_variable_get(:@num_chains)).to eq(3)
      expect(module_instance.instance_variable_get(:@comparison_strategy)).to eq(:vote)
      expect(module_instance.instance_variable_get(:@temperature)).to eq(0.7)
    end

    it 'accepts custom configuration' do
      custom_module = described_class.new(
        signature,
        model: model,
        num_chains: 5,
        comparison_strategy: :llm_judge,
        temperature: 0.9
      )
      expect(custom_module.instance_variable_get(:@num_chains)).to eq(5)
      expect(custom_module.instance_variable_get(:@comparison_strategy)).to eq(:llm_judge)
      expect(custom_module.instance_variable_get(:@temperature)).to eq(0.9)
    end
  end

  describe '#forward' do
    let(:inputs) { { question: 'What is 2 + 2?' } }

    context 'with vote strategy' do
      let(:chain1_response) do
        {
          content: <<~RESPONSE,
            REASONING: Let me add 2 + 2. Two plus two equals four.
            ANSWER: 4
          RESPONSE
          metadata: {}
        }
      end

      let(:chain2_response) do
        {
          content: <<~RESPONSE,
            REASONING: I'll calculate 2 + 2. The sum is 4.
            ANSWER: 4
          RESPONSE
          metadata: {}
        }
      end

      let(:chain3_response) do
        {
          content: <<~RESPONSE,
            REASONING: Adding 2 and 2 gives us 5... wait, that's wrong. It's 4.
            ANSWER: 4
          RESPONSE
          metadata: {}
        }
      end

      before do
        allow(model).to receive(:complete).and_return(
          chain1_response,
          chain2_response,
          chain3_response
        )
      end

      it 'generates multiple chains and votes on the answer' do
        result = module_instance.forward(**inputs)

        expect(result[:answer]).to eq('4')
        expect(result[:reasoning]).to be_a(String)
        expect(model).to have_received(:complete).exactly(3).times
      end

      it 'uses the specified temperature for diversity' do
        expect(model).to receive(:complete).exactly(3).times do |args|
          expect(args[:temperature]).to eq(0.7)
          chain1_response
        end

        module_instance.forward(**inputs)
      end
    end

    context 'with different answers' do
      let(:chain_responses) do
        [
          { content: "REASONING: First approach\nANSWER: 4", metadata: {} },
          { content: "REASONING: Second approach\nANSWER: 4", metadata: {} },
          { content: "REASONING: Third approach\nANSWER: 5", metadata: {} }
        ]
      end

      before do
        allow(model).to receive(:complete).and_return(*chain_responses)
      end

      it 'selects the most common answer' do
        result = module_instance.forward(**inputs)
        expect(result[:answer]).to eq('4') # 2 votes for 4, 1 for 5
      end
    end

    context 'with llm_judge strategy' do
      let(:judge_module) do
        described_class.new(
          signature,
          model: model,
          comparison_strategy: :llm_judge
        )
      end

      let(:chain_responses) do
        [
          { content: "REASONING: Quick calculation\nANSWER: 4", metadata: {} },
          { content: "REASONING: Detailed steps\nANSWER: 4", metadata: {} },
          { content: "REASONING: Visual approach\nANSWER: 4", metadata: {} }
        ]
      end

      let(:judge_response) do
        {
          content: "After careful consideration, I select attempt 2 because it has the most detailed reasoning.",
          metadata: {}
        }
      end

      before do
        allow(model).to receive(:complete).and_return(
          *chain_responses,
          judge_response
        )
      end

      it 'uses LLM to judge the best chain' do
        result = judge_module.forward(**inputs)

        expect(result[:answer]).to eq('4')
        expect(result[:reasoning]).to include('Detailed steps')

        # 3 chains + 1 judge call
        expect(model).to have_received(:complete).exactly(4).times
      end

      it 'uses low temperature for judging' do
        judge_module.forward(**inputs)

        # Check that the judge call used low temperature
        expect(model).to have_received(:complete).with(
          hash_including(temperature: 0.1)
        ).at_least(:once)
      end
    end

    context 'with confidence strategy' do
      let(:confidence_module) do
        described_class.new(
          signature,
          model: model,
          comparison_strategy: :confidence
        )
      end

      let(:chain_responses) do
        [
          { content: "REASONING: Basic approach\nANSWER: 4", metadata: {} },
          { content: "REASONING: Thorough analysis\nANSWER: 4", metadata: {} },
          { content: "REASONING: Quick guess\nANSWER: 5", metadata: {} }
        ]
      end

      let(:confidence_responses) do
        [
          { content: "75", metadata: {} },
          { content: "95", metadata: {} },
          { content: "30", metadata: {} }
        ]
      end

      before do
        call_count = 0
        allow(model).to receive(:complete) do |args|
          call_count += 1
          if args[:messages][0][:content].include?('Rate your confidence')
            # For confidence rating calls (after chain generation)
            confidence_index = call_count - 4 # Adjust for 3 chain calls before confidence calls
            confidence_responses[confidence_index] || confidence_responses.last
          else
            # For chain generation calls
            chain_index = call_count - 1
            chain_responses[chain_index] || chain_responses.last
          end
        end
      end

      it 'selects the chain with highest confidence' do
        result = confidence_module.forward(**inputs)

        expect(result[:answer]).to eq('4')
        expect(result[:reasoning]).to include('Thorough analysis')
        # The confidence strategy should pick the chain with confidence 95 (second chain)
        # Note: The confidence is stored as metadata in the implementation
      end
    end

    context 'with comparison_data in signature' do
      let(:detailed_signature) do
        Desiru::Signature.new('question: string -> answer: string, comparison_data: hash')
      end
      let(:detailed_module) { described_class.new(detailed_signature, model: model) }

      let(:chain_responses) do
        [
          { content: "REASONING: Method A\nANSWER: 4", metadata: {} },
          { content: "REASONING: Method B\nANSWER: 4", metadata: {} },
          { content: "REASONING: Method C\nANSWER: 4", metadata: {} }
        ]
      end

      before do
        allow(model).to receive(:complete).and_return(*chain_responses)
      end

      it 'includes comparison metadata when requested' do
        result = detailed_module.forward(**inputs)

        expect(result[:comparison_data]).to be_a(Hash)
        expect(result[:comparison_data][:num_chains]).to eq(3)
        expect(result[:comparison_data][:strategy]).to eq(:vote)
        expect(result[:comparison_data][:all_chains]).to be_an(Array)
        expect(result[:comparison_data][:all_chains].length).to eq(3)
      end
    end

    context 'with structured answers' do
      let(:complex_signature) do
        Desiru::Signature.new('problem: string -> solution: string, explanation: string')
      end
      let(:complex_module) { described_class.new(complex_signature, model: model) }
      let(:complex_inputs) { { problem: 'Solve x + 3 = 7' } }

      let(:structured_responses) do
        [
          {
            content: <<~RESPONSE,
              REASONING: Subtract 3 from both sides to isolate x.
              ANSWER: solution: x = 4, explanation: Subtracting 3 from both sides gives x = 4
            RESPONSE
            metadata: {}
          },
          {
            content: <<~RESPONSE,
              REASONING: Move 3 to the right side of the equation.
              ANSWER: {solution: "x = 4", explanation: "7 - 3 = 4"}
            RESPONSE
            metadata: {}
          },
          {
            content: <<~RESPONSE,
              REASONING: Basic algebra to solve for x.
              ANSWER: solution: x = 4
              explanation: We subtract 3 from 7 to get 4
            RESPONSE
            metadata: {}
          }
        ]
      end

      before do
        allow(model).to receive(:complete).and_return(*structured_responses)
      end

      it 'handles structured multi-field answers' do
        result = complex_module.forward(**complex_inputs)

        expect(result[:solution]).to include('x = 4')
        expect(result[:explanation]).to be_a(String)
        expect(result[:explanation]).not_to be_empty
      end
    end

    context 'error handling' do
      it 'falls back to first chain on unknown strategy' do
        error_module = described_class.new(
          signature,
          model: model,
          comparison_strategy: :unknown_strategy
        )

        chain_response = {
          content: "REASONING: Fallback\nANSWER: 4",
          metadata: {}
        }
        allow(model).to receive(:complete).and_return(chain_response)

        result = error_module.forward(**inputs)
        expect(result[:answer]).to eq('4')
      end

      it 'handles malformed responses gracefully' do
        bad_responses = [
          { content: "Just the number 4", metadata: {} },
          { content: "REASONING: Good\nANSWER: 4", metadata: {} },
          { content: "", metadata: {} }
        ]

        allow(model).to receive(:complete).and_return(*bad_responses)

        expect { module_instance.forward(**inputs) }.not_to raise_error
      end
    end
  end

  describe 'integration with Desiru infrastructure' do
    it 'works with demos' do
      module_with_demos = described_class.new(
        signature,
        model: model,
        demos: [
          { question: 'What is 1 + 1?', answer: '2' }
        ]
      )

      expect(module_with_demos.demos).not_to be_empty
    end

    it 'supports async execution' do
      expect(described_class.ancestors).to include(Desiru::AsyncCapable)
    end

    it 'integrates with trace collection' do
      allow(model).to receive(:complete).and_return(
        { content: "REASONING: Test\nANSWER: 4", metadata: {} }
      )

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
