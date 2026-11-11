module RailsTestRerun
  class Parser
    SUMMARY = /^(\d+) runs, \d+ assertions, (\d+) failures, (\d+) errors, (\d+) skips(?:, 0 warnings)?$/
    OUTCOME = /^\s*(?:\d+\) )?(Failure|Error|Skipped):$/
    SELECTOR = /^(?:bin\/rails|rails|bundle exec rails) test (.+:\d+)$/

    def parse(output, exit_code:)
      text = output.gsub(/\e\[[0-?]*[ -\/]*[@-~]/, "").gsub("\r\n", "\n")
      summaries = text.scan(SUMMARY)
      raise Error, "Missing or ambiguous completed Rails test summary." unless summaries.length == 1

      runs, failures, errors, skips = summaries.first.map(&:to_i)
      raise Error, "Test exit status disagrees with its summary." unless exit_code == (failures + errors == 0 ? 0 : 1)

      records = if text.include?("\nFailed tests:\n")
                  deferred_records(text)
                else
                  inline_records(text)
                end
      outcomes = records.map(&:first)
      unless outcomes.count("Failure") == failures && outcomes.count("Error") == errors &&
          outcomes.count("Skipped") <= skips && failures + errors + skips <= runs
        raise Error, "Failure/error details do not match the test summary."
      end

      selectors = records.filter_map { |kind, selector| selector unless kind == "Skipped" }
      { "selectors" => selectors.uniq, "failures" => failures, "errors" => errors, "runs" => runs }
    end

    private

      def deferred_records(text)
        sections = text.split("\nFailed tests:\n")
        raise Error, "Ambiguous deferred test report." unless sections.length == 2

        outcomes = sections.first.scan(/^\s*\d+\) (Failure|Error|Skipped):$/).flatten
        snippets = sections.last.scan(SELECTOR).flatten
        outcomes = outcomes.reject { |kind| kind == "Skipped" } if snippets.length == outcomes.count { |kind| kind != "Skipped" }
        raise Error, "Cannot correlate Rails failure details with rerun selectors." unless outcomes.length == snippets.length

        outcomes.zip(snippets)
      end

      def inline_records(text)
        records = []
        pending = nil
        text.each_line(chomp: true) do |line|
          if (outcome = OUTCOME.match(line))
            pending ||= outcome[1]
          elsif (snippet = SELECTOR.match(line))
            raise Error, "Rerun selector without a test outcome." unless pending

            records << [pending, snippet[1]]
            pending = nil
          end
        end
        raise Error, "Test outcome without a rerun selector." if pending

        records
      end
  end
end
