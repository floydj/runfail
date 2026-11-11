Gem::Specification.new do |spec|
  spec.name = "rails-test-rerun"
  spec.version = "0.2.0"
  spec.summary = "Automatically record Rails test results and rerun failures with runfail"
  spec.authors = ["TeamSite contributors"]
  spec.homepage = "https://github.com/floydj/runfail"
  spec.required_ruby_version = ">= 4.0"
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "exe/*", "README.md"] }
  spec.bindir = "exe"
  spec.executables = ["runfail"]
  spec.require_paths = ["lib"]
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
end
