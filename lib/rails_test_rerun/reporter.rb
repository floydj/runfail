module RailsTestRerun
  module Plugin
    class << self
      attr_reader :session

      def start
        return if @session
        return unless ENV["RAILS_ENV"] == "test" && defined?(Rails::Command::TestCommand)

        @session = Reporter.new(State.new(Command.project_root(Dir.pwd)), result_path: ENV["RAILS_TEST_RERUN_RESULT_FILE"])
        Minitest.singleton_class.prepend(Completion)
        Minitest.after_run { @session.finish($!) }
        at_exit { @session.abort_unreported }
      end
    end

    module Completion
      def run_all_suites(*arguments)
        super.tap { RailsTestRerun::Plugin.session.suites_finished = true }
      end
    end
  end

  class Reporter < Minitest::AbstractReporter
    attr_writer :suites_finished

    def initialize(state, result_path: nil)
      @state = state
      @result_path = result_path || File.join(state.directory, "latest.json")
      @owner = Process.pid
      @lock = state.lock unless result_path
      @closed = false
      @reported = false
      @suites_finished = false
      @result = { "selectors" => [], "failures" => 0, "errors" => 0, "runs" => 0 }
      write("status" => "running", "source" => "minitest")
      @snapshot = @state.snapshot
      log = File.join(@state.directory, "latest.log")
      File.delete(log) if !result_path && File.exist?(log)
    rescue Error, SystemCallError
      @lock&.close
      raise
    end

    def record(result)
      @result["runs"] += 1
      return if result.passed? || result.skipped?

      @result[result.failure.is_a?(Minitest::UnexpectedError) ? "errors" : "failures"] += 1
      file, line = result.source_location
      raise Error, "runfail: failed test has no valid source location." unless file.is_a?(String) && line.is_a?(Integer) && line.positive?

      relative = Pathname.new(file).relative_path_from(Pathname.new(@state.root))
      @result["selectors"] << "#{relative}:#{line}"
    end

    def report
      @reported = true
    end

    def passed?
      true
    end

    def finish(exception = nil)
      return if @closed || Process.pid != @owner
      unless @suites_finished && @reported && (!exception || exception.is_a?(SystemExit) && exception.success?)
        invalidate("Test run did not complete normally. Run bin/rails test again.")
        return
      end

      selectors = @result.fetch("selectors").uniq
      write(@result.merge("status" => "complete", "source" => "minitest", "argv" => %w[bin/rails test],
                          "selectors" => selectors, "fingerprints" => @state.fingerprints(selectors, snapshot: @snapshot)))
    rescue Error, SystemCallError => error
      invalidate(error.message)
      raise
    ensure
      close if Process.pid == @owner
    end

    def abort_unreported
      return if @closed || @reported || Process.pid != @owner

      invalidate("Test process exited before results were reported. Run bin/rails test again.")
    ensure
      close if Process.pid == @owner && !@reported
    end

    private

      def invalidate(message)
        write("status" => "unusable", "source" => "minitest", "error" => message)
        warn "runfail: #{message}"
      end

      def write(data)
        @state.write(data, @result_path)
      end

      def close
        @lock&.close unless @closed
        @closed = true
      end
  end
end
