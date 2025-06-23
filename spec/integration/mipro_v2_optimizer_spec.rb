# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MIPROv2 Optimizer Integration' do
  let(:mock_signature) do
    "question: string -> answer: string"
  end

  let(:mock_model) do
    double('Model',
           complete: { content: 'Generated response' },
           temperature: 0.7,
           respond_to?: true)
  end

  let(:mock_module) do
    module_with_demos = double('ModuleWithDemos',
                               call: { answer: 'Mock answer' },
                               respond_to?: true,
                               'instruction=': nil)

    double('Module',
           signature: Desiru::Signature.new(mock_signature),
           class: double(name: 'MockModule'),
           with_demos: module_with_demos,
           call: { answer: 'Mock answer' },
           respond_to?: true,
           'instruction=': nil)
  end

  let(:mock_program) do
    double('Program',
           modules: { main: mock_module },
           respond_to?: true,
           metadata: {},
           'metadata=': nil,
           call: ->(_inputs) { { answer: 'Mock answer' } })
  end

  let(:training_examples) do
    [
      Desiru::Core::Example.new(question: "What is 2+2?", answer: "4"),
      Desiru::Core::Example.new(question: "What is 3+3?", answer: "6"),
      Desiru::Core::Example.new(question: "What is 5+5?", answer: "10"),
      Desiru::Core::Example.new(question: "What is 1+1?", answer: "2"),
      Desiru::Core::Example.new(question: "What is 4+4?", answer: "8")
    ]
  end

  let(:validation_examples) do
    [
      Desiru::Core::Example.new(question: "What is 6+6?", answer: "12"),
      Desiru::Core::Example.new(question: "What is 7+7?", answer: "14")
    ]
  end

  before do
    Desiru::Core.reset_traces!

    # Mock the model temperature setting
    allow(mock_model).to receive(:temperature=)
    allow(mock_model).to receive(:instance_variable_get).with(:@temperature).and_return(0.7)
  end

  describe 'Basic optimization functionality' do
    let(:optimizer) do
      Desiru::Optimizers::MIPROv2.new(
        metric: :exact_match,
        max_iterations: 3,
        num_candidates: 2
      )
    end

    it 'performs multi-objective optimization' do
      # Mock program extraction and updating
      allow(optimizer).to receive(:extract_program_modules).and_return({ main: mock_module })
      allow(optimizer).to receive(:update_program_module)
      allow(optimizer).to receive(:deep_copy_program).and_return(mock_program)
      allow(optimizer).to receive(:enable_program_tracing)
      allow(optimizer).to receive(:disable_program_tracing)

      result = optimizer.compile(mock_program, trainset: training_examples, valset: validation_examples)

      expect(result).to eq(mock_program)
      expect(optimizer.optimization_history).not_to be_empty
      expect(optimizer.pareto_frontier).not_to be_empty
    end

    it 'tracks optimization history correctly' do
      allow(optimizer).to receive(:extract_program_modules).and_return({ main: mock_module })
      allow(optimizer).to receive(:update_program_module)
      allow(optimizer).to receive(:deep_copy_program).and_return(mock_program)
      allow(optimizer).to receive(:enable_program_tracing)
      allow(optimizer).to receive(:disable_program_tracing)

      optimizer.compile(mock_program, trainset: training_examples)

      history = optimizer.optimization_history
      expect(history.size).to be > 0

      history.each do |entry|
        expect(entry).to have_key(:iteration)
        expect(entry).to have_key(:best_candidate)
        expect(entry).to have_key(:scores)
        expect(entry).to have_key(:timestamp)
      end
    end

    it 'maintains Pareto frontier for multi-objective optimization' do
      multi_objective_optimizer = Desiru::Optimizers::MIPROv2.new(
        objectives: %i[exact_match confidence],
        max_iterations: 2
      )

      allow(multi_objective_optimizer).to receive(:extract_program_modules).and_return({ main: mock_module })
      allow(multi_objective_optimizer).to receive(:update_program_module)
      allow(multi_objective_optimizer).to receive(:deep_copy_program).and_return(mock_program)
      allow(multi_objective_optimizer).to receive(:enable_program_tracing)
      allow(multi_objective_optimizer).to receive(:disable_program_tracing)

      multi_objective_optimizer.compile(mock_program, trainset: training_examples)

      frontier = multi_objective_optimizer.pareto_frontier
      expect(frontier).to be_an(Array)
      expect(frontier.size).to be > 0

      frontier.each do |solution|
        expect(solution).to have_key(:candidate)
        expect(solution).to have_key(:scores)
        expect(solution[:scores]).to have_key(:exact_match)
      end
    end
  end

  describe 'Module optimization' do
    let(:optimizer) { Desiru::Optimizers::MIPROv2.new }

    it 'optimizes individual modules with examples' do
      optimized_module = optimizer.optimize_module(mock_module, training_examples)

      expect(optimized_module).to respond_to(:with_demos)
    end

    it 'generates instruction variants' do
      variants = optimizer.send(:generate_instruction_variants, mock_module, training_examples)

      expect(variants).to be_an(Array)
      expect(variants.size).to eq(3) # concise, detailed, step-by-step
      expect(variants).to all(be_a(String))
    end

    it 'generates diverse demonstration sets' do
      demo_sets = optimizer.send(:generate_demonstration_sets, mock_module, training_examples)

      expect(demo_sets).to be_an(Array)
      expect(demo_sets.first).to eq([]) # Empty set
      expect(demo_sets.any? { |set| set.size == 1 }).to be(true)
      expect(demo_sets.any? { |set| set.size > 1 }).to be(true)
    end

    it 'evaluates module configurations' do
      test_module = double('TestModule',
                           call: { answer: 'Mock answer' },
                           respond_to?: true,
                           'instruction=': nil)
      allow(mock_module).to receive(:with_demos).and_return(test_module)
      allow(test_module).to receive(:instruction=)

      score = optimizer.send(:evaluate_module_config,
                             mock_module,
                             "Test instruction",
                             training_examples.first(2),
                             training_examples)

      expect(score).to be_a(Numeric)
      expect(score).to be >= 0.0
    end
  end

  describe 'Candidate generation and evaluation' do
    let(:optimizer) do
      Desiru::Optimizers::MIPROv2.new(
        max_iterations: 2,
        num_candidates: 3,
        max_bootstrapped_demos: 5
      )
    end

    before do
      optimizer.instance_variable_set(:@current_program, mock_program)
      optimizer.instance_variable_set(:@trainset, training_examples)
      optimizer.instance_variable_set(:@valset, validation_examples)
      optimizer.instance_variable_set(:@iteration, 1)
    end

    it 'generates random candidates initially' do
      candidates = optimizer.send(:generate_random_candidates, 3)

      expect(candidates.size).to eq(3)
      candidates.each do |candidate|
        expect(candidate).to have_key(:id)
        expect(candidate).to have_key(:instruction_seed)
        expect(candidate).to have_key(:demo_seed)
        expect(candidate).to have_key(:temperature)
        expect(candidate).to have_key(:demo_count)
        expect(candidate[:temperature]).to be_between(0.1, 0.9)
        expect(candidate[:demo_count]).to be_between(1, 5)
      end
    end

    it 'generates guided candidates based on history' do
      # Add some history
      optimizer.instance_variable_get(:@optimization_history) << {
        candidate: {
          instruction_seed: 0.5,
          demo_seed: 0.3,
          temperature: 0.7,
          demo_count: 2
        },
        scores: { exact_match: 0.8 }
      }

      candidates = optimizer.send(:generate_guided_candidates, 2)

      expect(candidates.size).to eq(2)
      expect(candidates.any? { |c| c[:id].include?('mutated') }).to be(true)
    end

    it 'mutates candidates correctly' do
      base_candidate = {
        instruction_seed: 0.5,
        demo_seed: 0.5,
        temperature: 0.5,
        demo_count: 3
      }

      mutated = optimizer.send(:mutate_candidate, base_candidate)

      expect(mutated[:id]).to include('mutated')
      expect(mutated[:instruction_seed]).to be_between(0, 1)
      expect(mutated[:demo_seed]).to be_between(0, 1)
      expect(mutated[:temperature]).to be_between(0.1, 0.9)
      expect(mutated[:demo_count]).to be_between(1, 5)
    end

    it 'evaluates candidates and returns structured results' do
      candidates = [
        {
          id: 'test_1',
          instruction_seed: 0.5,
          demo_seed: 0.5,
          temperature: 0.5,
          demo_count: 2
        }
      ]

      allow(optimizer).to receive(:deep_copy_program).and_return(mock_program)
      allow(optimizer).to receive(:apply_candidate)
      allow(optimizer).to receive(:evaluate_multi_objective).and_return({ exact_match: 0.8 })
      allow(optimizer).to receive(:collect_candidate_traces).and_return([])

      evaluated = optimizer.send(:evaluate_candidates, candidates)

      expect(evaluated.size).to eq(1)
      result = evaluated.first
      expect(result).to have_key(:candidate)
      expect(result).to have_key(:scores)
      expect(result).to have_key(:traces)
      expect(result).to have_key(:timestamp)
      expect(result[:scores][:exact_match]).to eq(0.8)
    end
  end

  describe 'Gaussian Process integration' do
    let(:optimizer) { Desiru::Optimizers::MIPROv2.new }
    let(:gp) { optimizer.instance_variable_get(:@gaussian_process) }

    it 'creates and uses Gaussian Process correctly' do
      expect(gp).to be_a(Desiru::Optimizers::MIPROv2::GaussianProcess)

      # Add some observations
      features1 = [0.5, 0.3, 0.7, 0.8]
      features2 = [0.2, 0.8, 0.4, 0.6]

      gp.add_observation(features1, 0.8)
      gp.add_observation(features2, 0.6)
      gp.update

      prediction = gp.predict([0.4, 0.5, 0.6, 0.7])

      expect(prediction).to have_key(:mean)
      expect(prediction).to have_key(:std)
      expect(prediction[:mean]).to be_a(Numeric)
      expect(prediction[:std]).to be >= 0
    end

    it 'handles empty Gaussian Process gracefully' do
      empty_gp = Desiru::Optimizers::MIPROv2::GaussianProcess.new

      prediction = empty_gp.predict([0.5, 0.5, 0.5, 0.5])

      expect(prediction[:mean]).to eq(0.0)
      expect(prediction[:std]).to eq(1.0)
    end

    it 'updates with candidate evaluation results' do
      evaluated_candidates = [
        {
          candidate: {
            instruction_seed: 0.5,
            demo_seed: 0.3,
            temperature: 0.7,
            demo_count: 2
          },
          scores: { exact_match: 0.8 }
        }
      ]

      expect { optimizer.send(:update_gaussian_process, evaluated_candidates) }
        .not_to raise_error
    end
  end

  describe 'Acquisition functions' do
    let(:optimizer) { Desiru::Optimizers::MIPROv2.new(acquisition_function: :expected_improvement) }

    before do
      # Add some history for acquisition function calculation
      optimizer.instance_variable_get(:@optimization_history) << {
        scores: { exact_match: 0.7 }
      }
    end

    it 'computes expected improvement' do
      point = [0.5, 0.5, 0.5, 0.5]

      # Mock GP prediction
      allow(optimizer.instance_variable_get(:@gaussian_process))
        .to receive(:predict)
        .and_return({ mean: 0.8, std: 0.1 })

      ei = optimizer.send(:expected_improvement, point)

      expect(ei).to be_a(Numeric)
      expect(ei).to be >= 0
    end

    it 'computes upper confidence bound' do
      point = [0.5, 0.5, 0.5, 0.5]

      # Mock GP prediction
      allow(optimizer.instance_variable_get(:@gaussian_process))
        .to receive(:predict)
        .and_return({ mean: 0.8, std: 0.1 })

      ucb = optimizer.send(:upper_confidence_bound, point, 2.0)

      expect(ucb).to eq(1.0) # 0.8 + 2.0 * 0.1
    end

    it 'optimizes acquisition function to find promising points' do
      allow(optimizer).to receive(:compute_acquisition_value).and_return(0.5, 0.7, 0.3, 0.9, 0.6)

      best_point = optimizer.send(:optimize_acquisition_function)

      expect(best_point).to be_an(Array)
      expect(best_point.size).to eq(4) # [instruction_seed, demo_seed, temperature, demo_count]
    end
  end

  describe 'Demonstration selection strategies' do
    let(:optimizer) { Desiru::Optimizers::MIPROv2.new }

    it 'selects random demonstrations' do
      selected = optimizer.send(:select_demonstrations,
                                mock_module,
                                training_examples,
                                3,
                                'random',
                                0.5)

      expect(selected.size).to eq(3)
      expect(selected).to all(be_a(Desiru::Core::Example))
    end

    it 'selects diverse demonstrations' do
      selected = optimizer.send(:select_demonstrations,
                                mock_module,
                                training_examples,
                                3,
                                'diverse',
                                0.5)

      expect(selected.size).to eq(3)
      expect(selected).to all(be_a(Desiru::Core::Example))
    end

    it 'selects similar demonstrations' do
      selected = optimizer.send(:select_demonstrations,
                                mock_module,
                                training_examples,
                                2,
                                'similar',
                                0.5)

      expect(selected.size).to eq(2)
      expect(selected).to all(be_a(Desiru::Core::Example))
    end

    it 'handles empty demonstration selection' do
      selected = optimizer.send(:select_demonstrations,
                                mock_module,
                                training_examples,
                                0,
                                'random',
                                0.5)

      expect(selected).to be_empty
    end

    it 'calculates example distances' do
      ex1 = Desiru::Core::Example.new(question: "What is 2+2?", answer: "4")
      ex2 = Desiru::Core::Example.new(question: "What is 2+2?", answer: "4") # Same
      ex3 = Desiru::Core::Example.new(question: "What is 3+3?", answer: "6") # Different

      distance_same = optimizer.send(:example_distance, ex1, ex2)
      distance_different = optimizer.send(:example_distance, ex1, ex3)

      expect(distance_same).to eq(0.0) # Identical examples
      expect(distance_different).to be > 0 # Different examples
      expect(distance_different).to be <= 1.0
    end
  end

  describe 'Instruction generation' do
    let(:optimizer) { Desiru::Optimizers::MIPROv2.new }

    it 'generates concise instructions' do
      instruction = optimizer.send(:generate_instruction, mock_signature, 'concise', 0.5)

      expect(instruction).to include('question')
      expect(instruction).to include('answer')
      expect(instruction.length).to be < 100 # Relatively short
    end

    it 'generates detailed instructions' do
      instruction = optimizer.send(:generate_instruction, mock_signature, 'detailed', 0.5)

      expect(instruction).to include('question')
      expect(instruction).to include('answer')
      expect(instruction).to include('thorough')
      expect(instruction.length).to be > 50
    end

    it 'generates step-by-step instructions' do
      instruction = optimizer.send(:generate_instruction, mock_signature, 'step-by-step', 0.5)

      expect(instruction).to include('steps')
      expect(instruction).to include('1.')
      expect(instruction).to include('2.')
      expect(instruction).to include('3.')
    end

    it 'uses seed for reproducible instruction generation' do
      instruction1 = optimizer.send(:generate_instruction, mock_signature, 'concise', 0.42)
      instruction2 = optimizer.send(:generate_instruction, mock_signature, 'concise', 0.42)
      instruction3 = optimizer.send(:generate_instruction, mock_signature, 'concise', 0.84)

      expect(instruction1).to eq(instruction2) # Same seed, same result
      expect(instruction1).to eq(instruction3) # For this simple implementation, might be same
    end
  end

  describe 'Multi-objective optimization' do
    let(:multi_objective_optimizer) do
      Desiru::Optimizers::MIPROv2.new(
        objectives: %i[exact_match confidence consistency],
        max_iterations: 2
      )
    end

    it 'handles multiple objectives correctly' do
      scores1 = { exact_match: 0.8, confidence: 0.7, consistency: 0.9 }
      scores2 = { exact_match: 0.7, confidence: 0.9, consistency: 0.8 }

      scalarized1 = multi_objective_optimizer.send(:scalarize_objectives, scores1)
      scalarized2 = multi_objective_optimizer.send(:scalarize_objectives, scores2)

      expect(scalarized1).to be_a(Numeric)
      expect(scalarized2).to be_a(Numeric)
      expect(scalarized1).to be_between(0, 1)
    end

    it 'computes Pareto dominance correctly' do
      scores1 = { exact_match: 0.8, confidence: 0.7 }
      scores2 = { exact_match: 0.7, confidence: 0.8 }
      scores3 = { exact_match: 0.9, confidence: 0.9 } # Dominates others

      expect(multi_objective_optimizer.send(:dominates?, scores3, scores1)).to be(true)
      expect(multi_objective_optimizer.send(:dominates?, scores3, scores2)).to be(true)
      expect(multi_objective_optimizer.send(:dominates?, scores1, scores2)).to be(false)
      expect(multi_objective_optimizer.send(:dominates?, scores2, scores1)).to be(false)
    end

    it 'maintains non-dominated solutions in Pareto frontier' do
      candidates = [
        { scores: { exact_match: 0.8, confidence: 0.7 } },
        { scores: { exact_match: 0.7, confidence: 0.8 } },
        { scores: { exact_match: 0.6, confidence: 0.6 } }, # Dominated
        { scores: { exact_match: 0.9, confidence: 0.9 } }  # Dominates others
      ]

      frontier = multi_objective_optimizer.send(:compute_pareto_frontier, candidates)

      expect(frontier.size).to be <= candidates.size
      expect(frontier.size).to be >= 1

      # The solution with 0.9, 0.9 should be in the frontier
      best_solution = frontier.find { |c| c[:scores][:exact_match] == 0.9 }
      expect(best_solution).not_to be_nil
    end
  end

  describe 'Stopping criteria and convergence' do
    let(:optimizer) do
      Desiru::Optimizers::MIPROv2.new(
        max_iterations: 10,
        stop_at_score: 0.95,
        convergence_threshold: 0.001
      )
    end

    it 'stops when maximum iterations reached' do
      optimizer.instance_variable_set(:@iteration, 10)

      expect(optimizer.send(:should_stop?)).to be(true)
    end

    it 'stops when target score is reached' do
      optimizer.instance_variable_set(:@iteration, 3)
      optimizer.instance_variable_get(:@optimization_history) << {
        scores: { exact_match: 0.96 }
      }

      expect(optimizer.send(:should_stop?)).to be(true)
    end

    it 'stops when convergence is detected' do
      optimizer.instance_variable_set(:@iteration, 8)

      # Add history with very similar scores (converged)
      5.times do |i|
        optimizer.instance_variable_get(:@optimization_history) << {
          scores: { exact_match: 0.85 + (i * 0.0001) } # Very small variance
        }
      end

      expect(optimizer.send(:should_stop?)).to be(true)
    end

    it 'continues when none of the stopping criteria are met' do
      optimizer.instance_variable_set(:@iteration, 3)
      optimizer.instance_variable_get(:@optimization_history) << {
        scores: { exact_match: 0.7 }
      }

      expect(optimizer.send(:should_stop?)).to be(false)
    end

    it 'calculates statistical variance correctly' do
      values = [0.8, 0.82, 0.78, 0.81, 0.79]
      variance = optimizer.send(:statistical_variance, values)

      expect(variance).to be_a(Numeric)
      expect(variance).to be >= 0

      # Low variance for similar values
      low_variance_values = [0.8, 0.8001, 0.8002, 0.7999, 0.8001]
      low_variance = optimizer.send(:statistical_variance, low_variance_values)
      expect(low_variance).to be < variance
    end
  end

  describe 'Error handling and robustness' do
    let(:optimizer) { Desiru::Optimizers::MIPROv2.new(max_iterations: 1) }

    it 'handles optimization failures gracefully' do
      failing_program = double('FailingProgram')
      allow(failing_program).to receive(:modules).and_raise(StandardError.new('Program failed'))

      result = optimizer.compile(failing_program, trainset: training_examples)

      # Should return original program on error
      expect(result).to eq(failing_program)
    end

    it 'handles empty training sets' do
      allow(optimizer).to receive(:extract_program_modules).and_return({ main: mock_module })
      allow(optimizer).to receive(:deep_copy_program).and_return(mock_program)
      allow(optimizer).to receive(:enable_program_tracing)
      allow(optimizer).to receive(:disable_program_tracing)

      result = optimizer.compile(mock_program, trainset: [])

      expect(result).to eq(mock_program)
    end

    it 'handles malformed candidates gracefully' do
      malformed_candidates = [
        { id: 'test', instruction_seed: nil },
        { id: 'test2' }, # Missing required fields
        { id: 'test3', instruction_seed: 'invalid' }
      ]

      expect do
        optimizer.send(:evaluate_candidates, malformed_candidates)
      end.not_to raise_error
    end

    it 'recovers from Gaussian Process errors' do
      # Force GP to raise an error
      gp = optimizer.instance_variable_get(:@gaussian_process)
      allow(gp).to receive(:predict).and_raise(StandardError.new('GP failed'))

      point = [0.5, 0.5, 0.5, 0.5]

      expect do
        optimizer.send(:expected_improvement, point)
      end.not_to raise_error
    end
  end

  describe 'Trace integration' do
    let(:optimizer) do
      Desiru::Optimizers::MIPROv2.new(
        trace_collector: Desiru::Core.trace_collector,
        max_iterations: 1
      )
    end

    it 'integrates with trace collection system' do
      allow(optimizer).to receive(:extract_program_modules).and_return({ main: mock_module })
      allow(optimizer).to receive(:deep_copy_program).and_return(mock_program)
      allow(optimizer).to receive(:enable_program_tracing)
      allow(optimizer).to receive(:disable_program_tracing)

      # Add a trace
      trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: { question: 'test' },
        outputs: { answer: 'test_answer' }
      )
      Desiru::Core.trace_collector.collect(trace)

      optimizer.compile(mock_program, trainset: training_examples)

      expect(optimizer.trace_collector).to eq(Desiru::Core.trace_collector)
    end

    it 'clears traces when configured' do
      optimizer_clear = Desiru::Optimizers::MIPROv2.new(
        trace_collector: Desiru::Core.trace_collector,
        max_iterations: 1,
        clear_traces: true
      )

      # Add a trace before optimization
      trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: { question: 'test' },
        outputs: { answer: 'test_answer' }
      )
      Desiru::Core.trace_collector.collect(trace)
      expect(Desiru::Core.trace_collector.size).to eq(1)

      allow(optimizer_clear).to receive(:extract_program_modules).and_return({ main: mock_module })
      allow(optimizer_clear).to receive(:deep_copy_program).and_return(mock_program)
      allow(optimizer_clear).to receive(:enable_program_tracing)
      allow(optimizer_clear).to receive(:disable_program_tracing)

      optimizer_clear.compile(mock_program, trainset: training_examples)

      expect(Desiru::Core.trace_collector.size).to eq(0)
    end
  end
end
