# frozen_string_literal: true

# Specs that read a stored rule text through RecurringSeries, as the feeds do.
module SeriesHelpers
  def series_result(rule, start, from, to, limit)
    RecurringSeries.new(rule: rule, starts_at: start, ends_at: start).occurrences_starting_in(from..to, limit: limit)
  end

  def series_starts(rule, start, from, to, limit)
    series_result(rule, start, from, to, limit).occurrences.map(&:starts_at)
  end
end

RSpec.configure { |config| config.include SeriesHelpers }
