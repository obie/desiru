# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MultiChainComparison Module Integration' do
  let(:signature) do
    "question: string, context: string -> answer: string, reasoning: string, confidence: float, comparison_data: hash"
  end

  let(:test_inputs) do
    {
      question: "What is the capital of France?",
      context: "This is a geography question about European capitals."
    }
  end

  let(:mock_responses) do
    [
      "REASONING: France is a country in Europe. Its capital city is Paris, which is also the largest city in France.\nANSWER: Paris",
      "REASONING: Looking at European geography, France's capital has been Paris since the country was unified. Paris is located in northern France.\nANSWER: Paris",
      "REASONING: The capital of France is the city where the French government is based. This is Paris, home to the Élysée Palace and other government buildings.\nANSWER: Paris"
    ]
  end

  let(:mock_model) do
    model = double('Model')
    call_count = 0
    allow(model).to receive(:complete) do |_args|
      response = mock_responses[call_count % mock_responses.size]
      call_count += 1
      { content: response }
    end
    model
  end

  before do
    Desiru::Core.reset_traces!
  end

  describe 'Basic multi-chain generation' do
    let(:multi_chain) do
      Desiru::Modules::MultiChainComparison.new(
        signature,
        model: mock_model,
        num_chains: 3,
        comparison_strategy: :vote
      )
    end

    it 'generates multiple reasoning chains' do
      result = multi_chain.forward(**test_inputs)

      expect(result[:answer]).to eq("Paris")
      expect(result[:reasoning]).to be_a(String)
      expect(result[:reasoning]).to include("France")
    end

    it 'uses voting strategy to select best answer' do
      result = multi_chain.forward(**test_inputs)

      expect(result[:answer]).to eq("Paris") # All chains agree
      expect(mock_model).to have_received(:complete).exactly(3).times
    end

    it 'includes comparison metadata when requested' do
      result = multi_chain.forward(**test_inputs)

      expect(result[:comparison_data]).to be_a(Hash)
      expect(result[:comparison_data][:num_chains]).to eq(3)
      expect(result[:comparison_data][:strategy]).to eq(:vote)
      expect(result[:comparison_data][:all_chains]).to be_an(Array)
      expect(result[:comparison_data][:all_chains].size).to eq(3)
    end

    it 'generates distinct prompts for each chain' do
      captured_prompts = []
      allow(mock_model).to receive(:complete) do |args|
        captured_prompts << args[:messages].first[:content]
        { content: mock_responses[captured_prompts.size - 1] }
      end

      multi_chain.forward(**test_inputs)

      expect(captured_prompts.size).to eq(3)
      captured_prompts.each_with_index do |prompt, index|
        expect(prompt).to include("Approach #{index + 1}")
      end
    end
  end

  describe 'Different comparison strategies' do
    context 'voting strategy' do
      let(:voting_module) do
        Desiru::Modules::MultiChainComparison.new(
          signature,
          model: mock_model,
          num_chains: 3,
          comparison_strategy: :vote
        )
      end

      it 'selects most common answer' do
        # Mock responses where majority agrees
        conflicting_responses = [
          "REASONING: Paris is the capital.\nANSWER: Paris",
          "REASONING: Paris is the capital.\nANSWER: Paris",
          "REASONING: Maybe Lyon?\nANSWER: Lyon"
        ]

        conflicting_model = double('Model')
        call_count = 0
        allow(conflicting_model).to receive(:complete) do
          response = conflicting_responses[call_count]
          call_count += 1
          { content: response }
        end

        conflicting_module = Desiru::Modules::MultiChainComparison.new(
          signature,
          model: conflicting_model,
          num_chains: 3,
          comparison_strategy: :vote
        )

        result = conflicting_module.forward(**test_inputs)

        expect(result[:answer]).to eq("Paris") # Majority wins
      end
    end

    context 'LLM judge strategy' do
      let(:judge_module) do
        Desiru::Modules::MultiChainComparison.new(
          signature,
          model: mock_model,
          num_chains: 2,
          comparison_strategy: :llm_judge
        )
      end

      it 'uses LLM to judge between alternatives' do
        # Mock the judge response
        judge_response = "Attempt 1 provides the most comprehensive reasoning with historical context. I select attempt 1."

        # First two calls for chain generation, third for judging
        call_count = 0
        allow(mock_model).to receive(:complete) do
          call_count += 1
          if call_count <= 2
            { content: mock_responses[call_count - 1] }
          else
            { content: judge_response }
          end
        end

        result = judge_module.forward(**test_inputs)

        expect(result[:answer]).to eq("Paris")
        expect(mock_model).to have_received(:complete).exactly(3).times # 2 chains + 1 judge
      end

      it 'generates appropriate judge prompt' do
        judge_prompt = nil
        call_count = 0
        allow(mock_model).to receive(:complete) do |args|
          call_count += 1
          if call_count <= 2
            { content: mock_responses[call_count - 1] }
          else
            judge_prompt = args[:messages].first[:content]
            { content: "I select attempt 1." }
          end
        end

        judge_module.forward(**test_inputs)

        expect(judge_prompt).to include("select the best answer")
        expect(judge_prompt).to include("Original Problem")
        expect(judge_prompt).to include("Solution Attempts")
        expect(judge_prompt).to include("--- Attempt 1 ---")
        expect(judge_prompt).to include("--- Attempt 2 ---")
      end
    end

    context 'confidence strategy' do
      let(:confidence_module) do
        Desiru::Modules::MultiChainComparison.new(
          signature,
          model: mock_model,
          num_chains: 2,
          comparison_strategy: :confidence
        )
      end

      it 'selects chain with highest confidence' do
        confidence_responses = %w[85 92] # Confidence ratings

        call_count = 0
        allow(mock_model).to receive(:complete) do
          call_count += 1
          if call_count <= 2
            { content: mock_responses[call_count - 1] }
          else
            { content: confidence_responses[(call_count - 3) % 2] }
          end
        end

        result = confidence_module.forward(**test_inputs)

        expect(result[:answer]).to eq("Paris")
        expect(mock_model).to have_received(:complete).exactly(4).times # 2 chains + 2 confidence ratings
      end
    end
  end

  describe 'Response parsing' do
    let(:multi_chain) do
      Desiru::Modules::MultiChainComparison.new(
        signature,
        model: mock_model,
        num_chains: 1
      )
    end

    it 'parses structured responses correctly' do
      structured_response = "REASONING: This is my reasoning process step by step.\nANSWER: Paris\nconfidence: 0.95"

      allow(mock_model).to receive(:complete).and_return({ content: structured_response })

      result = multi_chain.forward(**test_inputs)

      expect(result[:answer]).to eq("Paris")
      expect(result[:reasoning]).to include("reasoning process")
      expect(result[:confidence]).to eq("0.95")
    end

    it 'handles responses without clear structure' do
      unstructured_response = "Well, the capital of France is definitely Paris. I'm quite sure about this."

      allow(mock_model).to receive(:complete).and_return({ content: unstructured_response })

      result = multi_chain.forward(**test_inputs)

      expect(result[:reasoning]).to eq(unstructured_response)
      expect(result[:answer]).to be_nil # No clear ANSWER: section
    end

    it 'parses key-value pairs in answers' do
      kv_response = "REASONING: Looking this up.\nANSWER: answer: Paris, confidence: 0.9, source: geography"

      allow(mock_model).to receive(:complete).and_return({ content: kv_response })

      result = multi_chain.forward(**test_inputs)

      expect(result[:answer]).to eq("Paris")
      expect(result[:confidence]).to eq("0.9")
    end

    it 'handles malformed responses gracefully' do
      malformed_responses = [
        "",
        "REASONING: \nANSWER: ",
        "Just some random text",
        "REASONING: Good reasoning\nWRONG_LABEL: Paris"
      ]

      malformed_responses.each do |response|
        allow(mock_model).to receive(:complete).and_return({ content: response })

        expect { multi_chain.forward(**test_inputs) }.not_to raise_error
      end
    end
  end

  describe 'Temperature and diversity' do
    it 'uses specified temperature for diversity' do
      high_temp_module = Desiru::Modules::MultiChainComparison.new(
        signature,
        model: mock_model,
        num_chains: 2,
        temperature: 0.9
      )

      expect(mock_model).to receive(:complete).with(
        hash_including(temperature: 0.9)
      ).twice.and_return({ content: mock_responses.first })

      high_temp_module.forward(**test_inputs)
    end

    it 'generates diverse reasoning approaches' do
      captured_prompts = []
      allow(mock_model).to receive(:complete) do |args|
        captured_prompts << args[:messages].first[:content]
        { content: mock_responses[captured_prompts.size - 1] }
      end

      multi_chain = Desiru::Modules::MultiChainComparison.new(
        signature,
        model: mock_model,
        num_chains: 3
      )

      multi_chain.forward(**test_inputs)

      # Each prompt should be slightly different to encourage diversity
      expect(captured_prompts.uniq.size).to eq(3)
    end
  end

  describe 'Complex reasoning scenarios' do
    let(:complex_signature) do
      "problem: string -> solution: string, steps: array, reasoning: string, comparison_data: hash"
    end

    let(:math_responses) do
      [
        "REASONING: I'll solve this step by step using algebra.\nANSWER: solution: x = 5, steps: [\"2x + 3 = 13\", \"2x = 10\", \"x = 5\"]",
        "REASONING: Using substitution method to solve.\nANSWER: solution: x = 5, steps: [\"Let y = 2x + 3\", \"y = 13\", \"2x = 10\", \"x = 5\"]",
        "REASONING: Direct calculation approach.\nANSWER: solution: x = 5, steps: [\"2x = 13 - 3\", \"2x = 10\", \"x = 5\"]"
      ]
    end

    it 'handles complex multi-field outputs' do
      math_model = double('Model')
      call_count = 0
      allow(math_model).to receive(:complete) do
        response = math_responses[call_count % math_responses.size]
        call_count += 1
        { content: response }
      end

      complex_module = Desiru::Modules::MultiChainComparison.new(
        complex_signature,
        model: math_model,
        num_chains: 3,
        comparison_strategy: :vote
      )

      result = complex_module.forward(problem: "Solve 2x + 3 = 13")

      expect(result[:solution]).to eq("x = 5")
      expect(result[:reasoning]).to be_a(String)
      expect(result[:comparison_data][:num_chains]).to eq(3)
    end

    it 'maintains reasoning quality across multiple chains' do
      math_model = double('Model')
      allow(math_model).to receive(:complete) do |args|
        prompt = args[:messages].first[:content]

        # Verify prompt contains problem context
        expect(prompt).to include("2x + 3 = 13")
        expect(prompt).to include("solution")
        expect(prompt).to include("steps")

        { content: math_responses.sample }
      end

      complex_module = Desiru::Modules::MultiChainComparison.new(
        complex_signature,
        model: math_model,
        num_chains: 3
      )

      complex_module.forward(problem: "Solve 2x + 3 = 13")
    end
  end

  describe 'Error handling and edge cases' do
    let(:multi_chain) do
      Desiru::Modules::MultiChainComparison.new(
        signature,
        model: mock_model,
        num_chains: 2
      )
    end

    it 'handles model failures gracefully' do
      failing_model = double('Model')
      allow(failing_model).to receive(:complete).and_raise(StandardError.new('Model failed'))

      failing_module = Desiru::Modules::MultiChainComparison.new(
        signature,
        model: failing_model,
        num_chains: 2
      )

      expect { failing_module.forward(**test_inputs) }.to raise_error(StandardError)
    end

    it 'handles empty responses' do
      empty_model = double('Model')
      allow(empty_model).to receive(:complete).and_return({ content: "" })

      empty_module = Desiru::Modules::MultiChainComparison.new(
        signature,
        model: empty_model,
        num_chains: 2
      )

      result = empty_module.forward(**test_inputs)

      expect(result[:reasoning]).to eq("")
      expect(result[:answer]).to be_nil
    end

    it 'handles single chain correctly' do
      single_chain = Desiru::Modules::MultiChainComparison.new(
        signature,
        model: mock_model,
        num_chains: 1
      )

      result = single_chain.forward(**test_inputs)

      expect(result[:answer]).to eq("Paris")
      expect(result[:comparison_data][:num_chains]).to eq(1)
    end

    it 'handles zero chains gracefully' do
      zero_chain = Desiru::Modules::MultiChainComparison.new(
        signature,
        model: mock_model,
        num_chains: 0
      )

      result = zero_chain.forward(**test_inputs)

      # Should return empty or default results
      expect(result).to be_a(Hash)
    end

    it 'validates comparison strategies' do
      expect do
        Desiru::Modules::MultiChainComparison.new(
          signature,
          model: mock_model,
          comparison_strategy: :invalid_strategy
        )
      end.not_to raise_error # Should use fallback or default
    end
  end

  describe 'Performance characteristics' do
    it 'scales reasonably with number of chains' do
      large_chain_module = Desiru::Modules::MultiChainComparison.new(
        signature,
        model: mock_model,
        num_chains: 10
      )

      start_time = Time.now
      result = large_chain_module.forward(**test_inputs)
      end_time = Time.now

      expect(end_time - start_time).to be < 2.0 # Should complete reasonably quickly
      expect(result[:comparison_data][:num_chains]).to eq(10)
      expect(mock_model).to have_received(:complete).exactly(10).times
    end

    it 'handles concurrent chain generation efficiently' do
      # This tests that the implementation doesn't have obvious bottlenecks
      concurrent_module = Desiru::Modules::MultiChainComparison.new(
        signature,
        model: mock_model,
        num_chains: 5
      )

      multiple_results = []
      3.times do
        multiple_results << concurrent_module.forward(**test_inputs)
      end

      expect(multiple_results.size).to eq(3)
      expect(multiple_results.all? { |r| r[:answer] == "Paris" }).to be(true)
    end
  end

  describe 'Integration with trace collection' do
    it 'works with trace collection enabled' do
      Desiru::Core.trace_context.with_trace(
        module_name: 'MultiChainComparison',
        signature: signature,
        inputs: test_inputs
      ) do
        multi_chain = Desiru::Modules::MultiChainComparison.new(
          signature,
          model: mock_model,
          num_chains: 2
        )

        multi_chain.forward(**test_inputs)
      end

      expect(Desiru::Core.trace_collector.size).to eq(1)

      trace = Desiru::Core.trace_collector.traces.first
      expect(trace.module_name).to eq('MultiChainComparison')
      expect(trace.inputs).to eq(test_inputs)
      expect(trace.success?).to be(true)
    end

    it 'captures chain comparison in trace metadata' do
      traced_module = Desiru::Modules::MultiChainComparison.new(
        signature,
        model: mock_model,
        num_chains: 3
      )

      result = traced_module.forward(**test_inputs)

      expect(result[:comparison_data]).to include(
        num_chains: 3,
        strategy: :vote,
        all_chains: an_instance_of(Array)
      )
    end
  end

  describe 'Real-world reasoning scenarios' do
    let(:reasoning_signature) do
      "scenario: string, constraints: array -> analysis: string, conclusion: string, evidence: array, reasoning: string, comparison_data: hash"
    end

    let(:reasoning_responses) do
      [
        "REASONING: Analyzing from economic perspective.\nANSWER: analysis: Economic factors suggest growth, conclusion: Invest, evidence: [\"GDP growth\", \"Low interest rates\"]",
        "REASONING: Focusing on risk management.\nANSWER: analysis: High market volatility presents risks, conclusion: Wait, evidence: [\"Market instability\", \"Political uncertainty\"]",
        "REASONING: Balanced view considering all factors.\nANSWER: analysis: Mixed signals in market, conclusion: Diversify, evidence: [\"Some positive indicators\", \"Some negative trends\"]"
      ]
    end

    it 'handles complex reasoning with multiple perspectives' do
      reasoning_model = double('Model')
      call_count = 0
      allow(reasoning_model).to receive(:complete) do
        if call_count < 3
          response = reasoning_responses[call_count]
          call_count += 1
          { content: response }
        else
          # This is the judge call
          call_count += 1
          { content: "Attempt 3 provides the most balanced analysis. I select attempt 3." }
        end
      end

      reasoning_module = Desiru::Modules::MultiChainComparison.new(
        reasoning_signature,
        model: reasoning_model,
        num_chains: 3,
        comparison_strategy: :llm_judge
      )

      result = reasoning_module.forward(
        scenario: "Should we invest in this market?",
        constraints: ["Budget limit", "Risk tolerance"]
      )

      expect(result[:conclusion]).to eq("Diversify")
      expect(result[:analysis]).to include("Mixed signals")
      expect(result[:comparison_data][:num_chains]).to eq(3)
    end
  end
end
