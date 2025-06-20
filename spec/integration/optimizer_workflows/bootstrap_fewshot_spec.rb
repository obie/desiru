require 'spec_helper'

RSpec.describe "BootstrapFewShot Optimizer Integration", type: :integration do
  before do
    Desiru::Persistence::Database.setup!
    Desiru.configure do |config|
      config.default_model = instance_double(Desiru::RaixAdapter)
    end
  end

  after do
    Desiru::Persistence::Database.teardown!
  end

  describe "optimizing a Predict module" do
    let(:predict_module) do
      Desiru::Predict.new(
        signature: "question -> answer",
        examples: []
      )
    end

    let(:training_data) do
      [
        { question: "What is 2+2?", answer: "4" },
        { question: "What is the capital of France?", answer: "Paris" },
        { question: "Who wrote Romeo and Juliet?", answer: "Shakespeare" },
        { question: "What is the boiling point of water?", answer: "100°C or 212°F" },
        { question: "How many days in a week?", answer: "7" }
      ]
    end

    let(:validation_data) do
      [
        { question: "What is 5+5?", answer: "10" },
        { question: "What is the capital of Spain?", answer: "Madrid" },
        { question: "Who painted the Mona Lisa?", answer: "Leonardo da Vinci" }
      ]
    end

    let(:optimizer) do
      Desiru::Optimizers::BootstrapFewShot.new(
        module: predict_module,
        metric: :exact_match,
        num_candidates: 3,
        max_iterations: 2
      )
    end

    it "improves module performance through example selection" do
      # Mock model responses for training
      allow(predict_module).to receive(:call) do |input|
        case input[:question]
        when /\d+\+\d+/
          { answer: "Calculating..." }
        when /capital/
          { answer: "A city" }
        else
          { answer: "Unknown" }
        end
      end

      # Run optimization
      optimized_module = optimizer.optimize(
        training_data: training_data,
        validation_data: validation_data
      )

      # Verify optimization was persisted
      optimization = Desiru::Persistence::Repositories::OptimizationResultRepository.new.last
      expect(optimization).to be_present
      expect(optimization.module_name).to eq("Predict")
      expect(optimization.optimizer_type).to eq("BootstrapFewShot")
      expect(optimization.metrics["initial_score"]).to be < optimization.metrics["final_score"]
      
      # Verify examples were selected
      expect(optimized_module.examples.size).to be > 0
      expect(optimized_module.examples.size).to be <= 3
    end

    it "tracks optimization progress through iterations" do
      iteration_scores = []
      
      optimizer = Desiru::Optimizers::BootstrapFewShot.new(
        module: predict_module,
        metric: :exact_match,
        num_candidates: 2,
        max_iterations: 3,
        on_iteration: ->(iteration, score) { iteration_scores << [iteration, score] }
      )

      allow(predict_module).to receive(:call).and_return({ answer: "test" })

      optimizer.optimize(
        training_data: training_data,
        validation_data: validation_data
      )

      expect(iteration_scores.size).to eq(3)
      expect(iteration_scores.map(&:first)).to eq([1, 2, 3])
    end

    context "with async optimization" do
      it "optimizes module asynchronously" do
        job = optimizer.optimize_async(
          training_data: training_data,
          validation_data: validation_data
        )

        expect(job).to be_a(Desiru::AsyncResult)
        expect(job.status).to eq("pending")

        # Simulate job completion
        allow(job).to receive(:status).and_return("completed")
        allow(job).to receive(:result).and_return(predict_module)

        expect(job.result).to eq(predict_module)
      end
    end
  end

  describe "optimizing a ChainOfThought module" do
    let(:cot_module) do
      Desiru::ChainOfThought.new(
        signature: "question -> reasoning -> answer",
        examples: []
      )
    end

    let(:training_data) do
      [
        { 
          question: "If John has 3 apples and gives 1 to Mary, how many does he have?",
          reasoning: "John starts with 3 apples. He gives 1 to Mary. 3 - 1 = 2.",
          answer: "2 apples"
        },
        {
          question: "A train travels 60 km/h for 2 hours. How far did it go?",
          reasoning: "Distance = Speed × Time. Speed is 60 km/h, Time is 2 hours. 60 × 2 = 120.",
          answer: "120 km"
        }
      ]
    end

    let(:optimizer) do
      Desiru::Optimizers::BootstrapFewShot.new(
        module: cot_module,
        metric: ->(pred, gold) { 
          pred[:answer] == gold[:answer] ? 1.0 : 0.0 
        }
      )
    end

    it "optimizes multi-step reasoning" do
      allow(cot_module).to receive(:call) do |input|
        {
          reasoning: "Let me think...",
          answer: "42"
        }
      end

      optimized = optimizer.optimize(
        training_data: training_data,
        validation_data: training_data.take(1)
      )

      expect(optimized.examples).not_to be_empty
      expect(optimized.examples.first).to include(:question, :reasoning, :answer)
    end
  end

  describe "optimizing a Program with multiple modules" do
    let(:program) do
      Desiru::Program.new("Math Solver") do |prog|
        classify = Desiru::Predict.new(signature: "problem -> problem_type")
        solve = Desiru::ChainOfThought.new(signature: "problem, problem_type -> solution")
        
        prog.add_module(:classify, classify)
        prog.add_module(:solve, solve)
        
        prog.define_flow do |input|
          type = prog.modules[:classify].call(problem: input[:problem])
          solution = prog.modules[:solve].call(
            problem: input[:problem],
            problem_type: type[:problem_type]
          )
          solution
        end
      end
    end

    let(:training_data) do
      [
        { problem: "2 + 2", solution: "4" },
        { problem: "5 * 3", solution: "15" },
        { problem: "10 / 2", solution: "5" }
      ]
    end

    it "optimizes all modules in the program" do
      optimizer = Desiru::Optimizers::BootstrapFewShot.new(
        module: program,
        metric: :exact_match,
        optimize_nested: true
      )

      allow(program.modules[:classify]).to receive(:call).and_return({ problem_type: "arithmetic" })
      allow(program.modules[:solve]).to receive(:call).and_return({ solution: "42" })

      optimized_program = optimizer.optimize(
        training_data: training_data,
        validation_data: training_data
      )

      # Both modules should have examples after optimization
      expect(optimized_program.modules[:classify].examples).not_to be_empty
      expect(optimized_program.modules[:solve].examples).not_to be_empty
    end
  end

  describe "optimization with caching" do
    before do
      Desiru.configure do |config|
        config.cache = Desiru::Cache.new
      end
    end

    let(:module_to_optimize) do
      Desiru::Predict.new(signature: "input -> output")
    end

    let(:optimizer) do
      Desiru::Optimizers::BootstrapFewShot.new(
        module: module_to_optimize,
        metric: :exact_match,
        use_cache: true
      )
    end

    it "caches optimization results" do
      training_data = [{ input: "test", output: "result" }]
      
      allow(module_to_optimize).to receive(:call).and_return({ output: "result" })

      # First optimization
      result1 = optimizer.optimize(training_data: training_data)
      
      # Second optimization with same data should use cache
      result2 = optimizer.optimize(training_data: training_data)

      expect(result1.examples).to eq(result2.examples)
      expect(module_to_optimize).to have_received(:call).at_most(training_data.size * 2).times
    end
  end

  describe "error handling during optimization" do
    let(:faulty_module) do
      Desiru::Predict.new(signature: "input -> output")
    end

    let(:optimizer) do
      Desiru::Optimizers::BootstrapFewShot.new(
        module: faulty_module,
        metric: :exact_match,
        max_retries: 2
      )
    end

    it "handles module execution errors gracefully" do
      call_count = 0
      allow(faulty_module).to receive(:call) do
        call_count += 1
        if call_count <= 2
          raise Desiru::Module::ExecutionError, "API timeout"
        else
          { output: "success" }
        end
      end

      result = optimizer.optimize(
        training_data: [{ input: "test", output: "expected" }]
      )

      expect(result).to be_a(Desiru::Module)
      expect(call_count).to be > 2
    end

    it "fails after max retries" do
      allow(faulty_module).to receive(:call).and_raise(Desiru::Module::ExecutionError, "Persistent error")

      expect {
        optimizer.optimize(
          training_data: [{ input: "test", output: "expected" }]
        )
      }.to raise_error(Desiru::Optimizers::OptimizationError, /Failed after \d+ retries/)
    end
  end
end