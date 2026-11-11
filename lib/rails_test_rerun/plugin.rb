require "minitest"
require_relative "../rails_test_rerun"
require_relative "reporter"
require_relative "../minitest/runfail_plugin"

Minitest.register_plugin("runfail") unless Minitest.extensions.include?("runfail")
RailsTestRerun::Plugin.start
