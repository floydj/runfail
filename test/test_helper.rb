require "minitest/autorun"
require "bundler"
require "open3"
require "stringio"
require "tmpdir"
require "timeout"
require_relative "../lib/rails_test_rerun"

module FixtureProject
  def with_project
    Dir.mktmpdir("rails-test-rerun-") do |root|
      FileUtils.mkdir_p(File.join(root, "bin"))
      FileUtils.mkdir_p(File.join(root, "test"))
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\ngem \"rails\", \"~> 8.1.0\"\n")
      File.write(File.join(root, "bin/rails"), <<~RUBY)
        #!/usr/bin/env ruby
        APP_PATH = File.expand_path("../config/application", __dir__)
        require "rails/commands"
      RUBY
      File.write(File.join(root, "config/application.rb"), <<~RUBY)
        require "rails"
        require "rails/test_unit/railtie"
        class FixtureApplication < Rails::Application
          config.eager_load = false
          config.secret_key_base = "test-fixture-not-a-production-secret"
          config.logger = Logger.new(File::NULL)
        end
      RUBY
      File.write(File.join(root, "config/environment.rb"), "require_relative \"application\"\nRails.application.initialize!\n")
      File.write(File.join(root, "Rakefile"), "require_relative \"config/application\"\nRails.application.load_tasks\n")
      File.chmod(0o755, File.join(root, "bin/rails"))
      File.write(File.join(root, "test/test_helper.rb"), <<~RUBY)
        require_relative "../config/environment"
        require "active_support/test_case"
        class FixtureCase < ActiveSupport::TestCase
          parallelize(workers: 2, threshold: 0)
          setup do
            File.open("executed.jsonl", "a") do |file|
              file.flock(File::LOCK_EX)
              file.puts JSON.generate(name: name, workers: ENV["PARALLEL_WORKERS"])
            end
          end
        end
      RUBY
      File.write(File.join(root, "test/first_test.rb"), <<~RUBY)
        require "json"
        require_relative "test_helper"
        class FirstTest < FixtureCase
          test("failure") { assert ENV["FIXTURE_PASS"] }
          test("error") { raise "fixture error" unless ENV["FIXTURE_PASS"]; assert true }
          test("passing") { assert true }
          test("skipped") { skip "fixture skip" }
        end
      RUBY
      File.write(File.join(root, "test/second_test.rb"), <<~RUBY)
        require "json"
        require_relative "test_helper"
        class SecondTest < FixtureCase
          test("other failure") { assert ENV["FIXTURE_PASS"] }
        end
      RUBY
      yield File.realpath(root)
    end
  end

  def with_environment(values)
    previous = values.to_h { |key, _| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def invoke(root, *arguments)
    output = StringIO.new
    error = StringIO.new
    code = RailsTestRerun::CLI.new(directory: root, output: output, error: error).run(arguments)
    [code, output.string, error.string]
  end

  def executed(root)
    File.readlines(File.join(root, "executed.jsonl")).map { |line| JSON.parse(line) }
  end

  def enable_plugin(root, path: nil)
    dependency = "gem \"rails-test-rerun\", require: \"rails_test_rerun/plugin\""
    dependency += ", path: #{path.inspect}" if path
    File.open(File.join(root, "Gemfile"), "a") { |file| file.puts "group :test do\n  #{dependency}\nend" }
    script = File.read(File.join(root, "bin/rails")).sub("APP_PATH", "require \"bundler/setup\"\nAPP_PATH")
    File.write(File.join(root, "bin/rails"), script)
    application = File.read(File.join(root, "config/application.rb"))
    application = application.sub("class FixtureApplication", "Bundler.require(:test)\nclass FixtureApplication")
    File.write(File.join(root, "config/application.rb"), application)
  end

  def plain_test(root, *arguments, environment: {})
    gemfile = File.join(root, "Gemfile")
    environment = { "BUNDLE_GEMFILE" => gemfile, "RAILS_ENV" => nil, "PARALLEL_WORKERS" => "2",
                    "FIXTURE_PASS" => nil, "RAILS_TEST_RERUN_RESULT_FILE" => nil }.merge(environment)
    Bundler.with_unbundled_env do
      Open3.capture3(environment, "bin/rails", "test", *arguments, chdir: root)
    end
  end

  def plugin_rerun(root, *arguments)
    with_environment("BUNDLE_GEMFILE" => File.join(root, "Gemfile"), "BUNDLE_LOCKFILE" => File.join(root, "Gemfile.lock"), "RUBYOPT" => nil) do
      invoke(root, *arguments)
    end
  end
end
