require "runfail"
require "runfail/reporter"

module Minitest
  def self.plugin_runfail_options(_parser, _options)
    Runfail::Plugin.start
  end

  def self.plugin_runfail_init(_options)
    Runfail::Plugin.start
    reporter << Runfail::Plugin.session if Runfail::Plugin.session
  end
end
