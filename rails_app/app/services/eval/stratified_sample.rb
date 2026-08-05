module Eval
  # Round-robins across a grouping key rather than taking a raw prefix — a
  # small sample must still span every group (e.g. every named module,
  # including apt_key's single deprecation question), not just whichever
  # group sorts first in the input. Confirmed live: an unstratified
  # `rows.first(limit)` sampled 18/18 questions from a single module.
  module StratifiedSample
    def self.take(rows, limit, by:)
      grouped = rows.group_by { |row| row[by] }.transform_values(&:dup)
      keys = grouped.keys

      sample = []
      keys.cycle do |key|
        break if sample.size >= limit || grouped.values.all?(&:empty?)

        row = grouped[key].shift
        sample << row if row
      end
      sample
    end
  end
end
