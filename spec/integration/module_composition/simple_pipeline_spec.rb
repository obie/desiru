require 'spec_helper'

RSpec.describe "Simple Module Pipeline Integration", type: :integration do
  before do
    Desiru.configure do |config|
      config.default_model = instance_double(Desiru::RaixAdapter, complete: "test response")
    end
  end

  describe "Predict → ChainOfThought pipeline" do
    let(:predict_module) do
      Desiru::Predict.new(
        signature: "question -> answer",
        examples: [
          { question: "What is 2+2?", answer: "4" },
          { question: "What color is the sky?", answer: "blue" }
        ]
      )
    end

    let(:cot_module) do
      Desiru::ChainOfThought.new(
        signature: "answer -> detailed_explanation",
        examples: [
          { 
            answer: "4", 
            detailed_explanation: "2+2 equals 4 because when you add 2 to 2, you get 4."
          }
        ]
      )
    end

    let(:program) do
      Desiru::Program.new("Q&A with Explanation") do |prog|
        prog.add_module(:predict, predict_module)
        prog.add_module(:cot, cot_module)
        
        prog.define_flow do |input|
          answer = prog.modules[:predict].call(question: input[:question])
          explanation = prog.modules[:cot].call(answer: answer[:answer])
          
          {
            question: input[:question],
            answer: answer[:answer],
            explanation: explanation[:detailed_explanation]
          }
        end
      end
    end

    it "executes modules in sequence" do
      allow(predict_module).to receive(:call).and_return({ answer: "Paris" })
      allow(cot_module).to receive(:call).and_return({ 
        detailed_explanation: "Paris is the capital of France, located in the north of the country."
      })

      result = program.call(question: "What is the capital of France?")

      expect(result[:question]).to eq("What is the capital of France?")
      expect(result[:answer]).to eq("Paris")
      expect(result[:explanation]).to include("Paris is the capital of France")
      
      expect(predict_module).to have_received(:call).with(question: "What is the capital of France?")
      expect(cot_module).to have_received(:call).with(answer: "Paris")
    end

    it "handles errors in pipeline gracefully" do
      allow(predict_module).to receive(:call).and_raise(Desiru::Module::ExecutionError, "LLM timeout")

      expect {
        program.call(question: "What is the meaning of life?")
      }.to raise_error(Desiru::Module::ExecutionError, /LLM timeout/)
    end

    context "with caching enabled" do
      before do
        Desiru.configure do |config|
          config.cache = Desiru::Cache.new
        end
      end

      it "caches intermediate results" do
        allow(predict_module).to receive(:call).and_return({ answer: "42" }).once
        allow(cot_module).to receive(:call).and_return({ 
          detailed_explanation: "42 is the answer to everything."
        }).once

        # First call
        result1 = program.call(question: "What is the answer?")
        
        # Second call with same input should use cache
        result2 = program.call(question: "What is the answer?")

        expect(result1).to eq(result2)
        expect(predict_module).to have_received(:call).once
      end
    end

    context "with persistence enabled" do
      before do
        Desiru::Persistence::Database.setup!
      end

      after do
        Desiru::Persistence::Database.teardown!
      end

      it "persists module execution results" do
        allow(predict_module).to receive(:call).and_return({ answer: "Blue" })
        allow(cot_module).to receive(:call).and_return({ 
          detailed_explanation: "The sky appears blue due to Rayleigh scattering."
        })

        result = program.call(question: "What color is the sky?")

        execution = Desiru::Persistence::Repositories::ModuleExecutionRepository.new.find_by_program("Q&A with Explanation")
        expect(execution).to be_present
        expect(execution.input_data).to eq({ "question" => "What color is the sky?" })
        expect(execution.output_data).to include("answer" => "Blue")
      end
    end
  end

  describe "Complex module composition with conditionals" do
    let(:classifier) do
      Desiru::Predict.new(
        signature: "text -> category",
        examples: [
          { text: "How do I install Ruby?", category: "technical" },
          { text: "What is love?", category: "philosophical" }
        ]
      )
    end

    let(:technical_handler) do
      Desiru::ChainOfThought.new(
        signature: "question -> technical_answer"
      )
    end

    let(:philosophical_handler) do
      Desiru::ReAct.new(
        signature: "question -> philosophical_answer",
        tools: []
      )
    end

    let(:program) do
      Desiru::Program.new("Adaptive Q&A") do |prog|
        prog.add_module(:classifier, classifier)
        prog.add_module(:technical, technical_handler)
        prog.add_module(:philosophical, philosophical_handler)
        
        prog.define_flow do |input|
          category_result = prog.modules[:classifier].call(text: input[:question])
          
          answer = case category_result[:category]
          when "technical"
            prog.modules[:technical].call(question: input[:question])
          when "philosophical"
            prog.modules[:philosophical].call(question: input[:question])
          else
            { answer: "I'm not sure how to answer that." }
          end
          
          {
            question: input[:question],
            category: category_result[:category],
            answer: answer[:answer] || answer[:technical_answer] || answer[:philosophical_answer]
          }
        end
      end
    end

    it "routes to appropriate handler based on classification" do
      allow(classifier).to receive(:call).with(text: "How do I debug Ruby code?").and_return({ category: "technical" })
      allow(technical_handler).to receive(:call).and_return({ technical_answer: "Use pry or byebug for debugging." })

      result = program.call(question: "How do I debug Ruby code?")

      expect(result[:category]).to eq("technical")
      expect(result[:answer]).to include("pry")
      expect(philosophical_handler).not_to have_received(:call)
    end

    it "handles unknown categories gracefully" do
      allow(classifier).to receive(:call).and_return({ category: "unknown" })

      result = program.call(question: "Random gibberish")

      expect(result[:category]).to eq("unknown")
      expect(result[:answer]).to eq("I'm not sure how to answer that.")
    end
  end
end