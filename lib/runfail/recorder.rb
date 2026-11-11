module Runfail
  class Recorder
    def initialize(state, output: $stdout)
      @state = state
      @output = output
    end

    def run(command, sequential: false)
      commands = Array(command)
      @state.write("status" => "running", "argv" => commands.first.argv)
      snapshot = @state.snapshot
      path = File.join(@state.directory, "latest.log")
      result = { "selectors" => [], "failures" => 0, "errors" => 0, "runs" => 0 }
      overall_code = 0
      exit_code = nil
      File.open(path, File::RDWR | File::CREAT | File::TRUNC | File::NOFOLLOW, 0o600) do |log|
        log.chmod(0o600)
        commands.each do |batch|
          offset = log.pos
          parsed = Tempfile.create(["result-", ".json"], @state.directory, mode: 0o600) do |file|
            exit_code = capture(batch.argv, log, sequential, file.path)
            overall_code = exit_code unless exit_code.zero?
            exported = File.read(file.path)
            if exported.empty?
              Parser.new.parse(File.read(path, log.pos - offset, offset), exit_code: exit_code)
            else
              structured_result(exported, exit_code)
            end
          end
          parsed.each { |key, value| result[key] += value }
        end
      end
      result["selectors"].uniq!
      @state.write(result.merge("status" => "complete", "argv" => commands.first.argv,
                               "fingerprints" => @state.fingerprints(result.fetch("selectors"), snapshot: snapshot)))
      overall_code
    rescue Error, SystemCallError, IOError => error
      @state.write("status" => "unusable", "error" => error.message)
      code = if exit_code && !exit_code.zero?
               exit_code
             elsif error.is_a?(Error)
               error.exit_status
             else
               1
             end
      raise Error.new(error.message, exit_status: code)
    end

    private

      def structured_result(exported, exit_code)
        data = JSON.parse(exported)
        unless data.is_a?(Hash) && data["status"] == "complete" && data["root"] == @state.root &&
            data["selectors"].is_a?(Array) && data["selectors"].all? { |selector| selector.is_a?(String) } &&
            %w[failures errors runs].all? { |key| data[key].is_a?(Integer) && data[key] >= 0 }
          raise Error, "Plugin did not produce completed test results."
        end
        failures = data.fetch("failures") + data.fetch("errors")
        unless exit_code == (failures.zero? ? 0 : 1) && failures <= data.fetch("runs")
          raise Error, "Test exit status disagrees with plugin results."
        end

        data.slice("selectors", "failures", "errors", "runs")
      rescue JSON::ParserError
        raise Error, "Plugin produced corrupt test results."
      end

      def capture(argv, log, sequential, result_path)
        reader, writer = IO.pipe
        pid = nil
        status = nil
        interrupted = nil
        previous_handlers = {}
        environment = { "RAILS_ENV" => "test", "RAILS_TEST_RERUN_RESULT_FILE" => result_path }
        environment["PARALLEL_WORKERS"] = "1" if sequential
        pid = Process.spawn(environment, *argv, chdir: @state.root, out: writer, err: writer, pgroup: true)
        child_pid = pid
        writer.close
        %w[INT TERM HUP].each do |signal|
          previous_handlers[signal] = Signal.trap(signal) do
            interrupted = Signal.list.fetch(signal)
            begin
              Process.kill(signal, -child_pid)
            rescue Errno::ESRCH
              # The child may have exited before the signal arrived.
            end
          end
        end
        loop do
          chunk = reader.readpartial(16_384)
          log.write(chunk)
          log.flush
          @output.write(chunk)
          @output.flush
        rescue EOFError
          break
        end
        _, status = Process.wait2(pid)
        pid = nil
        if interrupted || status.signaled?
          signal = interrupted || status.termsig
          raise Error.new("Test run interrupted (signal #{signal}).", exit_status: 128 + signal)
        end

        status.exitstatus
      ensure
        previous_handlers&.each { |signal, handler| Signal.trap(signal, handler) }
        reader&.close unless reader&.closed?
        writer&.close unless writer&.closed?
        if pid
          begin
            Process.kill("TERM", -pid)
          rescue Errno::ESRCH
            # Nothing remains to terminate.
          end
          Process.wait(pid)
        end
      end
  end
end
