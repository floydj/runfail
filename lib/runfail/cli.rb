module Runfail
  class CLI
    def initialize(directory: Dir.pwd, output: $stdout, error: $stderr)
      @directory = directory
      @output = output
      @error = error
    end

    def run(argv)
      arguments = argv.dup
      separator = arguments.include?("--")
      action = separator ? "run" : "rerun"
      action = arguments.shift if %w[run rerun].include?(arguments.first)
      sequential = false
      parser = OptionParser.new do |flags|
        flags.banner = "Usage: runfail [--sequential]\n       runfail [--sequential] -- bin/rails test [ARGS...]"
        flags.on("--sequential", "Disable parallel test workers for this invocation") { sequential = true }
        flags.on("-h", "--help", "Show usage") { @output.puts flags; return 0 }
      end
      parser.order!(arguments)
      raise Error, "Separate the Rails command with --." if action == "run" && !separator
      raise Error, parser.to_s if action == "rerun" && arguments.any?

      command = Command.new(arguments) if action == "run"
      state = State.new(Command.project_root(@directory))
      state.synchronize do
        if action == "rerun"
          data = state.read
          selectors = data.fetch("selectors")
          if selectors.empty?
            @output.puts "No failed tests in the latest completed run."
            return 0
          end
          raise Error, "Selected test files changed since the latest run. Record a new run." unless state.fingerprints(selectors) == data.fetch("fingerprints")

          command = Command.new(data.fetch("argv")).rerun_batches(selectors)
          @output.puts "Rerunning #{selectors.length} failed/errored tests in #{command.length} batch(es):"
          command.each { |batch| @output.puts Shellwords.join(batch.argv) }
        end
        Recorder.new(state, output: @output).run(command, sequential: sequential)
      end
    rescue Error => error
      @error.puts "Test rerun failed: #{error.message}"
      error.exit_status
    rescue OptionParser::ParseError, SystemCallError => error
      @error.puts "Test rerun failed: #{error.message}"
      1
    end
  end
end
