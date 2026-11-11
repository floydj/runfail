module RailsTestRerun
  class State
    attr_reader :root, :directory

    def initialize(root)
      @root = root
      @directory = File.join(root, "tmp", "rails-test-rerun")
      FileUtils.mkdir_p(directory, mode: 0o700)
      raise Error, "Capture directory must be inside this project, not a symlink." unless File.realpath(directory) == directory

      File.chmod(0o700, directory)
    end

    def synchronize
      handle = lock
      yield
    ensure
      handle&.close
    end

    def lock
      handle = File.open(File.join(directory, "lock"), File::RDWR | File::CREAT | File::NOFOLLOW, 0o600)
      unless handle.flock(File::LOCK_EX | File::LOCK_NB)
        handle.close
        raise Error, "Another test capture is running in this project."
      end
      handle
    end

    def write(data, path = File.join(directory, "latest.json"))
      raise Error, "Result file must be inside the private capture directory." unless File.dirname(path) == directory && !File.symlink?(path)

      Tempfile.create(["state-", ".json"], directory, mode: 0o600) do |file|
        file.write(JSON.generate(data.merge("version" => 1, "root" => root)))
        file.flush
        File.rename(file.path, path)
      end
    end

    def read
      data = JSON.parse(File.read(File.join(directory, "latest.json")))
      unless data.is_a?(Hash) && data["version"] == 1 && data["root"] == root
        raise Error, "Invalid capture metadata for this project."
      end
      raise Error, "Latest run is not usable: #{data.fetch("error", data["status"])}. Record a new run." unless data["status"] == "complete"
      unless data["argv"].is_a?(Array) && data["argv"].all? { |arg| arg.is_a?(String) } &&
          data["selectors"].is_a?(Array) && data["selectors"].all? { |selector| selector.is_a?(String) } &&
          data["fingerprints"].is_a?(Hash) && data["fingerprints"].keys.sort == data["selectors"].uniq.sort
        raise Error, "Invalid capture metadata. Record a new run."
      end

      Command.new(data["argv"])
      data
    rescue Errno::ENOENT
      raise Error, "No recorded test run. Enable the plugin and run bin/rails test first, or use runfail -- bin/rails test."
    rescue JSON::ParserError
      raise Error, "Corrupt capture metadata. Record a new run."
    end

    def snapshot
      Dir.glob(File.join(root, "test", "**", "*_test.rb")).filter_map do |path|
        next unless File.file?(path) && File.realpath(path).start_with?("#{root}/test/")

        [File.realpath(path), Digest::SHA256.file(path).hexdigest]
      end.to_h
    end

    def fingerprints(selectors, snapshot: nil)
      selectors.to_h do |selector|
        match = /\A(.+_test\.rb):([1-9]\d*)\z/.match(selector)
        raise Error, "Invalid test selector: #{selector.inspect}." unless match

        path = File.expand_path(match[1], root)
        unless File.file?(path) && File.realpath(path).start_with?("#{root}/test/") && match[2].to_i <= File.foreach(path).count
          raise Error, "Missing or out-of-project test selector: #{selector.inspect}."
        end

        digest = Digest::SHA256.file(path).hexdigest
        if snapshot && snapshot[File.realpath(path)] != digest
          raise Error, "Selected test files changed during the run. Record a new run."
        end

        [selector, digest]
      end
    end
  end
end
