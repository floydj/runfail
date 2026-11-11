module Runfail
  class Command
    TASK = /\Atest(?::(?:all|system|models|controllers|helpers|jobs|mailers|mailboxes|integration|units|functionals|generators|channels))?\z/

    def self.project_root(directory)
      current = Pathname.new(directory).realpath
      loop do
        return current.to_s if current.join("bin/rails").file? && current.join("Gemfile").file?
        raise Error, "Run this command inside a Rails project with Gemfile and bin/rails." if current.root?

        current = current.parent
      end
    end

    attr_reader :argv, :prefix

    def initialize(argv)
      @argv = argv
      @prefix, task = if argv.first == "bin/rails"
                        [argv.take(1), argv[1]]
                      elsif argv.take(3) == %w[bundle exec rails]
                        [argv.take(3), argv[3]]
                      end
      raise Error, "Expected bin/rails test or bundle exec rails test (including Rails test subcommands)." unless task && TASK.match?(task)
      raise Error, "Test runs must use the test environment." if argv.drop(prefix.length + 1).any? { |arg| arg.start_with?("-e", "--environment") }
    end

    def rerun(selectors)
      [*prefix, "test", *selectors, "-v", "-d"]
    end

    def rerun_batches(selectors, limit: 32_000)
      selectors.each_with_object([[]]) do |selector, batches|
        batches << [] if !batches.last.empty? && rerun(batches.last + [selector]).sum { |arg| arg.bytesize + 1 } > limit
        batches.last << selector
      end.map { |batch| self.class.new(rerun(batch)) }
    end
  end
end
