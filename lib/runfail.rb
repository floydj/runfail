require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "shellwords"
require "tempfile"

module RailsTestRerun
  class Error < StandardError
    attr_reader :exit_status

    def initialize(message, exit_status: 1)
      super(message)
      @exit_status = exit_status
    end
  end
end

require_relative "rails_test_rerun/command"
require_relative "rails_test_rerun/parser"
require_relative "rails_test_rerun/state"
require_relative "rails_test_rerun/recorder"
require_relative "rails_test_rerun/cli"
