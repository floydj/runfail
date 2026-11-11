require "runfail"
require "rails_test_rerun/reporter"

module Minitest
  def self.plugin_runfail_options(_parser, _options)
    RailsTestRerun::Plugin.start
  end

  def self.plugin_runfail_init(_options)
    RailsTestRerun::Plugin.start
    reporter << RailsTestRerun::Plugin.session if RailsTestRerun::Plugin.session
  end
end
