require "csv"

module Eval
  # Reads and writes data/ground_truth.csv — one row per ground-truth question,
  # shared between the parameter slice and the deprecation-overview slice
  # (nullable columns for whichever fields don't apply to a given row, rather
  # than two separate files — see design.md).
  #
  # Columns: id, module_fqcn, chunk_type ("parameter"|"overview"), stable_id,
  # question, expected_type, expected_default, expected_choices (pipe-joined),
  # expected_deprecated ("true"|"false", overview rows only),
  # expected_alternative (overview rows only), ansible_core_version, generated_at
  module GroundTruth
    HEADERS = %w[
      id module_fqcn chunk_type stable_id question
      expected_type expected_default expected_choices
      expected_deprecated expected_alternative
      ansible_core_version generated_at
    ].freeze

    DEFAULT_PATH = Rails.root.join("data/ground_truth.csv")

    def self.write(rows, path: DEFAULT_PATH)
      CSV.open(path, "w") do |csv|
        csv << HEADERS
        rows.each { |row| csv << serialize(row) }
      end
    end

    def self.serialize(row)
      HEADERS.map do |header|
        value = row[header.to_sym]
        header == "expected_choices" ? Array(value).join("|") : value
      end
    end
    private_class_method :serialize

    def self.load(path: DEFAULT_PATH)
      return [] unless File.exist?(path)

      CSV.read(path, headers: true).map do |row|
        {
          id: row["id"],
          module_fqcn: row["module_fqcn"],
          chunk_type: row["chunk_type"],
          stable_id: row["stable_id"],
          question: row["question"],
          expected_type: row["expected_type"],
          expected_default: row["expected_default"],
          expected_choices: row["expected_choices"].to_s.split("|"),
          expected_deprecated: row["expected_deprecated"] == "true",
          expected_alternative: row["expected_alternative"],
          ansible_core_version: row["ansible_core_version"],
          generated_at: row["generated_at"]
        }
      end
    end
  end
end
