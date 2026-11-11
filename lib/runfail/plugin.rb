require "minitest"
require_relative "../runfail"
require_relative "reporter"
require_relative "../minitest/runfail_plugin"

Minitest.register_plugin("runfail") unless Minitest.extensions.include?("runfail")
Runfail::Plugin.start
