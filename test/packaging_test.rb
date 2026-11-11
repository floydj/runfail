require "test_helper"
require "rubygems/package"

class PackagingTest < Minitest::Test
  include FixtureProject

  def test_installed_gem_can_record_and_rerun_in_another_rails_repository
    gem_root = File.expand_path("..", __dir__)
    Dir.mktmpdir("rails-test-rerun-install-") do |destination|
      artifact = File.join(destination, "utility.gem")
      output, error, status = Open3.capture3(RbConfig.ruby, "-S", "gem", "build", "rails-test-rerun.gemspec",
                                            "--output", artifact, chdir: gem_root)
      assert status.success?, output + error
      contents = Gem::Package.new(artifact).contents
      assert_equal ["exe/runfail"], contents.grep(%r{\Aexe/})
      assert_empty contents.grep(%r{\A(?:test|tmp|config)/})
      home = File.join(destination, "home")
      environment = { "GEM_HOME" => home, "GEM_PATH" => [home, *Gem.path].join(File::PATH_SEPARATOR),
                      "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "PARALLEL_WORKERS" => "2", "FIXTURE_PASS" => nil }
      Bundler.with_unbundled_env do
        output, error, status = Open3.capture3(environment, RbConfig.ruby, "-S", "gem", "install", "--local", artifact,
                                              "--install-dir", home, "--no-document")
        assert status.success?, output + error
        executable = File.join(home, "bin/runfail")
        output, error, status = Open3.capture3(environment, executable, "--help")
        assert status.success?, output + error
        assert_includes output, "Usage: runfail [--sequential]\n"
        with_project do |root|
          enable_plugin(root)
          output, error, status = Open3.capture3(environment, "bin/rails", "test", chdir: root)
          assert_equal 1, status.exitstatus, output + error
          assert_empty error
          assert_equal 3, RailsTestRerun::State.new(root).read.fetch("selectors").length
          assert_equal "minitest", RailsTestRerun::State.new(root).read.fetch("source")
          File.delete(File.join(root, "executed.jsonl"))
          output, error, status = Open3.capture3(environment, executable, chdir: root)
          assert_equal 1, status.exitstatus, output + error
          assert_empty error
          assert_equal %w[test_error test_failure test_other_failure], executed(root).map { |row| row.fetch("name") }.sort
          assert_equal ["2"], executed(root).map { |row| row.fetch("workers") }.uniq
          assert_equal %w[-v -d], RailsTestRerun::State.new(root).read.fetch("argv").last(2)
          File.delete(File.join(root, "executed.jsonl"))
          output, error, status = Open3.capture3(environment.merge("FIXTURE_PASS" => "1"), executable, "--sequential",
                                                chdir: root)
          assert status.success?, output + error
          assert_equal 3, executed(root).length
          assert_equal ["1"], executed(root).map { |row| row.fetch("workers") }.uniq
          output, error, status = Open3.capture3(environment, executable, chdir: root)
          assert status.success?, output + error
          assert_includes output, "No failed tests"
          assert_equal 3, executed(root).length
        end
      end
    end
  end
end
