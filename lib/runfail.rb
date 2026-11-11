require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "shellwords"
require "tempfile"

module Runfail
  class Error < StandardError
    attr_reader :exit_status

    def initialize(message, exit_status: 1)
      super(message)
      @exit_status = exit_status
    end
  end
end

require_relative "runfail/command"
require_relative "runfail/parser"
require_relative "runfail/state"
require_relative "runfail/recorder"
require_relative "runfail/cli"
