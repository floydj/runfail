require "test_helper"

class UtilityTest < Minitest::Test
  include FixtureProject

  def test_help_and_invalid_arguments_do_not_require_a_project
    assert_equal 0, invoke("/", "--help").first
    assert_includes invoke("/", "--help")[1], "runfail [--sequential] -- bin/rails test"
    assert_equal 0, invoke("/", "--sequential", "--help").first
    assert_equal 1, invoke("/", "--sequential", "bin/rails", "test").first
    assert_equal 1, invoke("/", "run", "bin/rails", "test").first
    assert_equal 1, invoke("/", "run", "--", "sh", "-c", "anything").first
    assert_equal 1, invoke("/", "rerun", "test/models").first
    assert_equal 1, invoke("/", "run", "--", "bin/rails", "test", "--environment=production").first
  end

  def test_default_and_sequential_reruns_report_missing_capture_instead_of_showing_usage
    with_project do |root|
      [[], ["--sequential"]].each do |arguments|
        code, _, error = invoke(root, *arguments)
        assert_equal 1, code
        assert_includes error, "No recorded test run."
      end
    end
  end

  def test_short_recording_form_supports_sequential_and_preserves_runner_arguments
    with_project do |root|
      with_environment("PARALLEL_WORKERS" => "2", "FIXTURE_PASS" => nil) do
        arguments = %w[bin/rails test test/first_test.rb -v -d]
        code, output, error = invoke(root, "--sequential", "--", *arguments)
        assert_equal 1, code, error + output
        assert_empty error
        assert_equal arguments, Runfail::State.new(root).read.fetch("argv")
        assert_equal 4, executed(root).length
        assert_equal ["1"], executed(root).map { |row| row.fetch("workers") }.uniq
        assert_equal "2", ENV["PARALLEL_WORKERS"]
      end
    end
  end

  def test_runner_grammar_and_exact_rerun_argv
    %w[test test:all test:system test:models test:mailboxes].each do |task|
      command = Runfail::Command.new(["bundle", "exec", "rails", task, "-n", "old_filter", "-f", "--seed", "42"])
      assert_equal ["bundle", "exec", "rails", "test", "test/first_test.rb:4", "-v", "-d"], command.rerun(["test/first_test.rb:4"])
    end
    assert_raises(Runfail::Error) { Runfail::Command.new(%w[bin/rails db:drop]) }
  end

  def test_state_errors_isolation_locking_and_source_changes
    with_project do |root|
      state = Runfail::State.new(root)
      assert_raises(Runfail::Error) { state.read }
      File.write(File.join(state.directory, "latest.json"), "{bad json")
      assert_raises(Runfail::Error) { state.read }
      state.write("status" => "running")
      assert_raises(Runfail::Error) { state.read }
      state.write("status" => "complete", "argv" => [], "selectors" => "not an array")
      assert_raises(Runfail::Error) { state.read }
      state.synchronize do
        assert_raises(Runfail::Error) { Runfail::State.new(root).synchronize { } }
      end
      selectors = ["test/first_test.rb:4"]
      state.write("status" => "complete", "argv" => %w[bin/rails test], "selectors" => selectors,
                  "fingerprints" => state.fingerprints(selectors))
      File.open(File.join(root, "test/first_test.rb"), "a") { |file| file.puts "# changed" }
      code, _, error = invoke(root, "rerun")
      assert_equal 1, code
      assert_includes error, "changed"
      with_project do |other_root|
        assert_raises(Runfail::Error) { Runfail::State.new(other_root).read }
      end
    end
  end

  def test_selector_validation_rejects_missing_external_and_symlinked_paths
    with_project do |root|
      state = Runfail::State.new(root)
      ["test/missing_test.rb:3", "../other_test.rb:3", "test/first_test.rb:99999", "test/first_test.rb:0",
       "test/first_test.rb:4; touch unwanted", "Gemfile:1"].each do |selector|
        assert_raises(Runfail::Error) { state.fingerprints([selector]) }
      end
      with_project do |other_root|
        File.symlink(File.join(other_root, "test/first_test.rb"), File.join(root, "test/linked_test.rb"))
        assert_raises(Runfail::Error) { state.fingerprints(["test/linked_test.rb:4"]) }
      end
    end
  end

  def test_real_parallel_runner_reruns_only_failures_and_errors_then_clears_state
    with_project do |root|
      with_environment("PARALLEL_WORKERS" => "2", "FIXTURE_PASS" => nil) do
        code, output, error = invoke(root, "run", "--", "bin/rails", "test", "-v", "-d")
        assert_equal 1, code, error + output
        assert_empty error
        assert_includes output, "parallel using 2"
        assert_equal 5, executed(root).length
        state = Runfail::State.new(root)
        assert_equal 3, state.read.fetch("selectors").length
        assert_equal 0o600, File.stat(File.join(state.directory, "latest.log")).mode & 0o777
        File.delete(File.join(root, "executed.jsonl"))

        with_environment("FIXTURE_PASS" => "1") do
          code, output, error = invoke(File.join(root, "test"), "rerun", "--sequential")
          assert_equal 0, code, error + output
          assert_includes output, "-v -d"
          assert_equal %w[test_error test_failure test_other_failure], executed(root).map { |row| row.fetch("name") }.sort
          assert_equal ["1"], executed(root).map { |row| row.fetch("workers") }.uniq
          assert_equal "2", ENV["PARALLEL_WORKERS"]
          assert_empty state.read.fetch("selectors")
          assert_equal 0, invoke(root, "rerun").first
          assert_equal 3, executed(root).length
        end
      end
    end
  end

  def test_real_inline_run_and_repeated_reruns_do_not_include_skips
    with_project do |root|
      with_environment("PARALLEL_WORKERS" => "1", "FIXTURE_PASS" => nil) do
        code, output, error = invoke(root, "run", "--", "bin/rails", "test", "-v")
        assert_equal 1, code, error + output
        assert_empty error
        File.delete(File.join(root, "executed.jsonl"))
        code, output, error = invoke(root, "rerun")
        assert_equal 1, code, error + output
        assert_empty error
        assert_equal %w[test_error test_failure test_other_failure], executed(root).map { |row| row.fetch("name") }.sort
        assert_equal 3, Runfail::State.new(root).read.fetch("selectors").length
      end
    end
  end

  def test_boot_failure_and_launch_failure_invalidate_previous_results
    with_project do |root|
      state = Runfail::State.new(root)
      state.write("status" => "complete", "argv" => %w[bin/rails test], "selectors" => [], "fingerprints" => {})
      File.write(File.join(root, "bin/rails"), "#!/usr/bin/env ruby\nwarn 'boot failed'\nexit 2\n")
      code, output, error = invoke(root, "run", "--", "bin/rails", "test")
      assert_equal 2, code
      assert_includes output, "boot failed"
      assert_includes error, "summary"
      assert_raises(Runfail::Error) { state.read }
      File.chmod(0o644, File.join(root, "bin/rails"))
      assert_equal 1, invoke(root, "run", "--", "bin/rails", "test").first
      assert_raises(Runfail::Error) { state.read }
    end
  end

  def test_capture_is_live_and_preserves_a_valid_test_exit_status
    with_project do |root|
      File.write(File.join(root, "bin/rails"), <<~RUBY)
        #!/usr/bin/env ruby
        $stdout.sync = true
        puts "ready"
        sleep 0.1 until File.exist?("continue")
        warn "stderr captured"
        puts "1 runs, 1 assertions, 0 failures, 0 errors, 0 skips"
      RUBY
      output = StringIO.new
      output.define_singleton_method(:write) do |chunk|
        File.write(File.join(root, "continue"), "") if chunk.include?("ready")
        super(chunk)
      end
      state = Runfail::State.new(root)
      assert_equal 0, Runfail::Recorder.new(state, output: output).run(Runfail::Command.new(%w[bin/rails test]))
      assert_includes output.string, "stderr captured"
      assert_equal output.string, File.read(File.join(state.directory, "latest.log"))
    end
  end

  def test_nonverbose_runner_formats_and_passing_run_replace_earlier_failures
    with_project do |root|
      with_environment("PARALLEL_WORKERS" => "1", "FIXTURE_PASS" => nil) do
        [[], ["-d"], ["-d", "--show-skips"]].each do |flags|
          code, output, error = invoke(root, "run", "--", "bin/rails", "test", *flags)
          assert_equal 1, code, error + output
          assert_empty error
          assert_equal 3, Runfail::State.new(root).read.fetch("selectors").length
        end
        with_environment("FIXTURE_PASS" => "1") do
          assert_equal 0, invoke(root, "run", "--", "bin/rails", "test").first
          assert_empty Runfail::State.new(root).read.fetch("selectors")
        end
      end
    end
  end

  def test_batched_reruns_continue_after_failure_and_publish_one_combined_result
    with_project do |root|
      with_environment("PARALLEL_WORKERS" => "1", "FIXTURE_PASS" => nil) do
        code, output, error = invoke(root, "run", "--", "bin/rails", "test")
        assert_equal 1, code, error + output
        state = Runfail::State.new(root)
        selectors = state.read.fetch("selectors")
        command = Runfail::Command.new(%w[bin/rails test -n old_filter -f])
        batches = command.rerun_batches(selectors, limit: 1)
        assert_equal 3, batches.length
        File.delete(File.join(root, "executed.jsonl"))
        output = StringIO.new
        state.synchronize do
          assert_equal 1, Runfail::Recorder.new(state, output: output).run(batches)
        end
        assert_equal 3, executed(root).length
        assert_equal selectors.sort, state.read.fetch("selectors").sort
      end
    end
  end

  def test_termination_reaches_child_invalidates_state_and_preserves_signal_exit_status
    with_project do |root|
      File.write(File.join(root, "bin/rails"), <<~RUBY)
        #!/usr/bin/env ruby
        trap("TERM") { File.write("terminated", "yes"); exit 143 }
        $stdout.sync = true
        puts "ready"
        sleep 30
      RUBY
      library = File.expand_path("../lib", __dir__)
      executable = File.expand_path("../exe/runfail", __dir__)
      Open3.popen3(RbConfig.ruby, "-I", library, executable, "run", "--", "bin/rails", "test", chdir: root) do |input, output, error, process|
        input.close
        assert_equal "ready\n", Timeout.timeout(10) { output.gets }
        Process.kill("TERM", process.pid)
        assert_equal 143, Timeout.timeout(10) { process.value.exitstatus }
        assert File.exist?(File.join(root, "terminated"))
        assert_includes error.read, "interrupted"
        assert_raises(Runfail::Error) { Runfail::State.new(root).read }
      ensure
        Process.kill("TERM", process.pid) if process.alive?
      end
    end
  end

  def test_a_source_edit_during_capture_does_not_publish_stale_selectors
    with_project do |root|
      File.write(File.join(root, "bin/rails"), <<~RUBY)
        #!/usr/bin/env ruby
        File.open("test/first_test.rb", "a") { |file| file.puts "# edited during test execution" }
        puts "Failure:"
        puts "ExampleTest#test_one:"
        puts "failed"
        puts "bin/rails test test/first_test.rb:4"
        puts "1 runs, 1 assertions, 1 failures, 0 errors, 0 skips"
        exit 1
      RUBY
      code, _, error = invoke(root, "run", "--", "bin/rails", "test")
      assert_equal 1, code
      assert_includes error, "changed during"
      assert_raises(Runfail::Error) { Runfail::State.new(root).read }
    end
  end

  def test_real_runner_with_both_assertion_failure_and_teardown_error
    with_project do |root|
      File.write(File.join(root, "test/first_test.rb"), <<~RUBY)
        require "json"
        require_relative "test_helper"
        class FirstTest < FixtureCase
          teardown { raise "teardown failed" }
          test("failure") { flunk "assertion failed" }
        end
      RUBY
      with_environment("PARALLEL_WORKERS" => "1") do
        [["-v"], ["-v", "-d"]].each do |flags|
          code, output, error = invoke(root, "run", "--", "bin/rails", "test", "test/first_test.rb", *flags)
          assert_equal 1, code, error + output
          assert_empty error
          assert_equal 1, Runfail::State.new(root).read.fetch("selectors").length
        end
      end
    end
  end
end
