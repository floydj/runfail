require "test_helper"

class PluginTest < Minitest::Test
  include FixtureProject

  def with_plugin_project
    with_project do |root|
      enable_plugin(root, path: File.expand_path("..", __dir__))
      yield root
    end
  end

  def test_plain_parallel_runs_record_structured_failures_without_a_wrapper
    with_plugin_project do |root|
      output, error, status = plain_test(root)
      assert_equal 1, status.exitstatus, output + error
      assert_empty error
      assert_includes output, "parallel using 2"
      state = RailsTestRerun::State.new(root)
      data = state.read
      assert_equal "minitest", data.fetch("source")
      assert_equal 5, data.fetch("runs")
      assert_equal 2, data.fetch("failures")
      assert_equal 1, data.fetch("errors")
      assert_equal 3, data.fetch("selectors").length
      assert_equal 0o600, File.stat(File.join(state.directory, "latest.json")).mode & 0o777

      File.delete(File.join(root, "executed.jsonl"))
      code, output, error = plugin_rerun(root, "--sequential")
      assert_equal 1, code, error + output
      assert_empty error
      assert_equal %w[test_error test_failure test_other_failure], executed(root).map { |row| row.fetch("name") }.sort
      assert_equal ["1"], executed(root).map { |row| row.fetch("workers") }.uniq
      assert_equal %w[-v -d], state.read.fetch("argv").last(2)
    end
  end

  def test_passes_and_skips_clear_previous_failures_and_output_logs
    with_plugin_project do |root|
      output, error, status = plain_test(root, "-v", "-d")
      assert_equal 1, status.exitstatus, output + error
      state = RailsTestRerun::State.new(root)
      File.write(File.join(state.directory, "latest.log"), "old wrapper output")
      output, error, status = plain_test(root, environment: { "FIXTURE_PASS" => "1" })
      assert status.success?, output + error
      assert_empty state.read.fetch("selectors")
      assert_equal 0, invoke(root).first
      assert_empty Dir.glob(File.join(state.directory, "latest.log"))
    end
  end

  def test_failure_after_plugin_load_invalidates_previous_results
    with_plugin_project do |root|
      plain_test(root)
      application = File.join(root, "config/application.rb")
      File.open(application, "a") { |file| file.puts "raise \"fixture boot error\"" }
      output, error, status = plain_test(root, "test/first_test.rb")
      assert_operator status.exitstatus, :>, 0, output + error
      assert_includes error, "fixture boot error"
      assert_includes error, "before results were reported"
      assert_raises(RailsTestRerun::Error) { RailsTestRerun::State.new(root).read }
    end
  end

  def test_interrupted_test_is_not_published_as_a_completed_run
    with_plugin_project do |root|
      plain_test(root)
      File.write(File.join(root, "test/interrupt_test.rb"), <<~RUBY)
        require_relative "test_helper"
        class InterruptTest < FixtureCase
          test("interrupted") { raise Interrupt }
        end
      RUBY
      output, error, status = plain_test(root, "test/interrupt_test.rb", environment: { "PARALLEL_WORKERS" => "1" })
      assert_operator status.exitstatus, :>, 0, output + error
      assert_includes error, "did not complete normally"
      assert_raises(RailsTestRerun::Error) { RailsTestRerun::State.new(root).read }
    end
  end

  def test_existing_capture_lock_blocks_a_plain_run_without_overwriting_state
    with_plugin_project do |root|
      state = RailsTestRerun::State.new(root)
      state.write("status" => "running", "marker" => "existing capture")
      state.synchronize do
        output, error, status = plain_test(root)
        assert_operator status.exitstatus, :>, 0, output + error
        assert_includes error, "Another test capture"
      end
      data = JSON.parse(File.read(File.join(state.directory, "latest.json")))
      assert_equal "existing capture", data.fetch("marker")
    end
  end

  def test_other_rails_commands_in_test_environment_do_not_start_a_capture
    with_plugin_project do |root|
      environment = { "BUNDLE_GEMFILE" => File.join(root, "Gemfile"), "RAILS_ENV" => "test" }
      output, error, status = Bundler.with_unbundled_env do
        Open3.capture3(environment, "bin/rails", "runner", "puts 'not a test run'", chdir: root)
      end
      assert status.success?, output + error
      assert_includes output, "not a test run"
      assert_empty Dir.glob(File.join(root, "tmp/rails-test-rerun/latest.json"))
    end
  end

  def test_reruns_use_structured_results_even_with_a_custom_console_summary
    with_plugin_project do |root|
      File.open(File.join(root, "test/test_helper.rb"), "a") do |file|
        file.puts <<~RUBY
          module CustomSummary
            def summary
              "Custom test summary without numeric totals"
            end
          end
          Minitest::SummaryReporter.prepend(CustomSummary)
        RUBY
      end
      output, error, status = plain_test(root)
      assert_equal 1, status.exitstatus, output + error
      assert_includes output, "Custom test summary"
      File.delete(File.join(root, "executed.jsonl"))
      code, output, error = plugin_rerun(root, "--sequential")
      assert_equal 1, code, error + output
      assert_empty error
      assert_equal 3, executed(root).length
      assert_equal 3, RailsTestRerun::State.new(root).read.fetch("selectors").length
    end
  end
end
