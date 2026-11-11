require "test_helper"

class ParserTest < Minitest::Test
  def parse(text, code = 1)
    RailsTestRerun::Parser.new.parse(text, exit_code: code).fetch("selectors")
  end

  def test_inline_failures_errors_and_verbose_skips
    text = <<~TEXT
      \e[31mFailure:\e[0m
      ExampleTest#test_one [test/example_test.rb:99]:
      Expected true
      bin/rails test test/example_test.rb:5
      Skipped:
      ExampleTest#test_skip:
      skip
      bin/rails test test/example_test.rb:8
      Error:
      ExampleTest#test_error:
      RuntimeError
      test/helpers/bogus_test.rb:300
      bin/rails test test/example_test.rb:12
      4 runs, 2 assertions, 1 failures, 1 errors, 1 skips
    TEXT
    assert_equal ["test/example_test.rb:5", "test/example_test.rb:12"], parse(text)
  end

  def test_deferred_results_align_skips_and_paths_with_spaces
    text = <<~TEXT
        1) Skipped:
      ExampleTest#test_skip:
      skip
        2) Failure:
      ExampleTest#test_one:
      failure
        3) Error:
      OtherTest#test_error:
      error
      4 runs, 2 assertions, 1 failures, 1 errors, 1 skips

      Failed tests:

      bin/rails test test/example_test.rb:8
      bin/rails test test/a space/example_test.rb:5
      bin/rails test test/other_test.rb:12
    TEXT
    assert_equal ["test/a space/example_test.rb:5", "test/other_test.rb:12"], parse(text)
  end

  def test_show_skips_without_verbose_does_not_require_a_skip_selector
    assert_equal ["test/example_test.rb:5"], parse(<<~TEXT)
      1) Skipped:
      skip
      2) Failure:
      failure
      2 runs, 1 assertions, 1 failures, 0 errors, 1 skips
      Failed tests:
      bin/rails test test/example_test.rb:5
    TEXT
  end

  def test_deduplicates_test_source_selectors
    assert_equal ["test/example_test.rb:5"], parse(<<~TEXT)
      Failure:
      bin/rails test test/example_test.rb:5
      Failure:
      bin/rails test test/example_test.rb:5
      2 runs, 2 assertions, 2 failures, 0 errors, 0 skips
    TEXT
  end

  def test_passing_run_has_no_selections
    assert_empty parse("3 runs, 3 assertions, 0 failures, 0 errors, 0 skips\n", 0)
  end

  def test_a_teardown_error_after_a_failure_is_one_failed_test
    ["", "  1) "].each do |prefix|
      body = <<~TEXT
        #{prefix}Failure:
        ExampleTest#test_one:
        assertion failed

        Error:
        ExampleTest#test_one:
        teardown failed
      TEXT
      selector = "bin/rails test test/example_test.rb:5\n"
      summary = "1 runs, 1 assertions, 1 failures, 0 errors, 0 skips\n"
      text = prefix.empty? ? body + selector + summary : body + summary + "\nFailed tests:\n" + selector
      assert_equal ["test/example_test.rb:5"], parse(text)
    end
  end

  def test_refuses_missing_ambiguous_mismatched_and_suppressed_results
    [
      "",
      "boot error\n",
      "1 runs, 1 assertions, 1 failures, 0 errors, 0 skips\n",
      "1 runs, 1 assertions, 0 failures, 0 errors, 0 skips\n",
      "1 runs, 1 assertions, 1 failures, 0 errors, 0 skips\n" * 2,
      "Failure:\nbin/rails test test/a_test.rb:3\n1 runs, 1 assertions, 0 failures, 1 errors, 0 skips\n"
    ].each do |text|
      assert_raises(RailsTestRerun::Error) { parse(text) }
    end
  end
end
