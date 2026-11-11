# Copilot instructions

## Build, test, and lint

Requires Ruby 4.0 or newer. From the repository root:

```sh
bundle install
bundle exec ruby -I test test/all_test.rb
bundle exec rubocop
gem build runfail.gemspec
```

Run one test file or one named test:

```sh
bundle exec ruby -I test test/parser_test.rb
bundle exec ruby -I test test/parser_test.rb --name test_inline_failures_and_verbose_skips
```

CI runs the full test file, RuboCop, and the gem build.

## Architecture

`exe/runfail` starts `Runfail::CLI`. `Command` finds the target Rails project, restricts supported Rails test tasks, and constructs reruns from failed-test selectors. The CLI and the Minitest plugin both use `State` to coordinate captures and persist the latest result under `tmp/runfail/`.

There are two recording paths. The `runfail -- bin/rails test ...` wrapper streams child output through `Recorder`; when the plugin is absent, `Parser` extracts failure selectors from Rails' text output. With `require: "runfail/plugin"` in the target app, the plugin attaches a Minitest `Reporter` to ordinary Rails test runs and records structured results, including with parallel workers. Both paths save source fingerprints so reruns are rejected if selected test files have changed.

## Repository-specific conventions

- The gem, executable, Ruby namespace (`Runfail`), implementation directory (`lib/runfail/`), and private state directory (`tmp/runfail/`) use the `runfail` name; keep these names aligned when changing code or tests.
- Tests use Minitest. `test/test_helper.rb` creates temporary Rails fixture projects, and plugin/packaging tests exercise real subprocesses; keep integration coverage in those fixtures rather than depending on a developer's Rails application.
- RuboCop is disabled by default and enables only the rules in `.rubocop.yml`. Keep to double-quoted strings and the configured internal-method indentation style.
