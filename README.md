# runfail

Automatically record Rails/Minitest results and use `runfail` to rerun every
failed or errored test, without rerunning passing or skipped tests. Developed in
TeamSite; maintained independently for use in other Rails repositories.
Originally tracked in [floydj/teamsite#985](https://github.com/floydj/teamsite/issues/985).
The gem and its executable are both named `runfail`.

## Install

Requires Ruby 4.0 or newer. Initially verified with Ruby 4.0.9, Rails 8.1.4.1,
and Minitest 6.1.0. Other runners and Rails versions are not supported.

Clone this repository, then build and install the executable:

```sh
git clone https://github.com/floydj/runfail.git
cd runfail
gem build runfail.gemspec --output /tmp/runfail-0.2.0.gem
gem install --local /tmp/runfail-0.2.0.gem --no-document
```

Add the plugin to each target application's Gemfile:

```ruby
group :test do
  gem "runfail", git: "https://github.com/floydj/runfail.git", require: "runfail/plugin"
end
```

Then run `bundle install` in the target application. Bundler locks the Git
revision in its lockfile. The gem is not published to RubyGems.
No changes to `test/test_helper.rb` are needed.

For local development against a sibling checkout, use
`path: "../runfail"` instead of `git:`. Do not commit machine-specific paths
to applications that need to build without that checkout.

The gem has no dependency on TeamSite application code. The target application
provides Rails and Minitest. `bundle exec runfail` also works without a separate
global installation when the gem is available through the project's bundle.
Installing the packaged gem provides bare `runfail` on your gem executable PATH.
Version 0.2 uses `runfail` as its executable.

## Usage

From any directory inside the target Rails project:

```sh
bin/rails test test/models
runfail
runfail --sequential
```

No wrapper is required: the Minitest reporter records structured results from
ordinary Rails test commands in the test environment, including parallel
workers. Passing runs clear earlier failures, and skipped tests are excluded.
Console output formatting does not affect integrated runs or their reruns.

All reruns enforce `RAILS_ENV=test`. Only run against disposable test databases.

Every failure rerun passes `-v` (verbose) and `-d` (defer failure/error output). The
`--sequential` feature flag sets `PARALLEL_WORKERS=1` **only in the child
process**. Without it, existing worker settings are inherited unchanged. There
is no interactive prompt. The selected commands are displayed before execution.
Large failure sets are split into batches; failing batches do not stop the rest.

Original path scopes, name/include/exclude filters, fail-fast, and other runner
options are not replayed. Automatic captures rerun through `bin/rails test`
with exact failed-test source selectors and `-v -d`. Set any desired environment
variables again when rerunning; historical environment overrides are not saved.

For applications without plugin integration, the optional wrapper still works:

```sh
runfail -- bin/rails test test/models
runfail --sequential -- bin/rails test test/models
```

Only this fallback requires parsing Rails' console output. Paths after `--`
are relative to the project root. With the plugin enabled, wrapped runs and
reruns use private per-child result files while the parent holds the project
lock; the plugin never competes with the command for that lock.

## Terminal compatibility and state

Use the same commands in Ghostty, iTerm2, and Terminal. The plugin works inside
Minitest, without scrollback access, terminal automation, clipboard access, or
Accessibility permissions. Plain test runs keep their normal terminal I/O.
An earlier run from before plugin installation cannot be recovered.

`runfail` streams subprocess stdout/stderr and inherits stdin. Its subprocess
output is piped rather than attached to a pseudo-terminal, so automatic color
may be disabled and full-screen TTY/debugger interaction is not provided.

The latest run is shared across tabs in each project. A rerun becomes the latest
run; subsequent reruns include only its remaining failures. A completed passing
run clears earlier failures, including when some tests were skipped.
Interrupted or fail-fast automatic runs are not published as completed captures.

Private local state lives in `tmp/runfail/`:

- `latest.log`: combined output from the latest command-managed run, if any.
  Plain plugin-recorded runs do not save a terminal transcript.
- `latest.json`: completion status, counts, selected source locations, and
  selected source-file fingerprints.
- `lock`: prevents concurrent captures from mixing results.

Keep this directory ignored by version control. Logs can contain application
data: do not upload them or commit them. Only the latest capture is retained.
State is local to the current checkout; separate worktrees are independent.

Missing/corrupt state, interrupted runs, boot errors after plugin loading,
missing tests, and changed test files produce explicit errors. They never select
the whole suite or silently reuse older failures. Run `bin/rails test` again to
recover. Errors before Bundler loads the plugin cannot be recorded; in that
case, the previous capture is unchanged. Normal test exit behavior is preserved.
`runfail` forwards Ctrl-C/termination to its owned child process group and
propagates test exit codes and signal exit statuses.

## Development

From this repository, install the standalone development dependencies and run:

```sh
bundle install
bundle exec ruby -I test test/all_test.rb
bundle exec rubocop
gem build runfail.gemspec
```

The GitHub Actions workflow runs the same tests and linter, and builds the gem.
No TeamSite checkout or configuration is needed.

Tests create disposable minimal Rails applications, without application
databases, browser drivers, or external services. They cover real
Rails output fallback and structured plugin results, parallel/sequential
execution, boot failures and interrupts, capture locking, custom summaries,
state validation, and local gem packaging/installation. Terminal-application
smoke checks supplement subprocess coverage; automated tests do not control
the user's terminal windows.
