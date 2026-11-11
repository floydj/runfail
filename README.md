# runfail

Automatically record Rails/Minitest results and use `runfail` to rerun every
failed or errored test.

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

Then run `bundle install` in the target application.
revision in its lockfile. The gem is not published to RubyGems.
No changes to `test/test_helper.rb` are needed.

For local development against a sibling checkout, use
`path: "../runfail"` instead of `git:`. 

`bundle exec runfail` also works without a separate
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

Every failure rerun passes `-v` (verbose) and `-d` (defer failure/error output). The
`--sequential` feature flag sets `PARALLEL_WORKERS=1` **only in the child
process**. Without it, existing worker settings are inherited unchanged.

For applications without plugin integration, you can use a wrapper:

```sh
runfail -- bin/rails test test/models
runfail --sequential -- bin/rails test test/models
```

## Terminal compatibility and state

`runfail` streams subprocess stdout/stderr and inherits stdin. Its subprocess
output is piped rather than attached to a pseudo-terminal, so automatic color
may be disabled and full-screen TTY/debugger interaction is not provided.

The latest run is shared across tabs in each project. A rerun becomes the latest
run; subsequent reruns include only its remaining failures.

Private local state lives in `tmp/runfail/`:

- `latest.log`: combined output from the latest command-managed run, if any.
  Plain plugin-recorded runs do not save a terminal transcript.
- `latest.json`: completion status, counts, selected source locations, and
  selected source-file fingerprints.
- `lock`: prevents concurrent captures from mixing results.

Keep this directory ignored by version control. Logs can contain application
data: do not upload them or commit them. Only the latest capture is retained.
State is local to the current checkout; separate worktrees are independent.

## Development

From this repository, install the standalone development dependencies and run:

```sh
bundle install
bundle exec ruby -I test test/all_test.rb
bundle exec rubocop
gem build runfail.gemspec
```
