require "test_helper"

module Eval
  class StratifiedSampleTest < ActiveSupport::TestCase
    def rows_for(module_fqcn, count)
      Array.new(count) { |i| { module_fqcn: module_fqcn, question: "#{module_fqcn} q#{i}" } }
    end

    test "spans every group instead of taking a raw prefix from one group" do
      rows = rows_for("ansible.builtin.apt", 20) + rows_for("ansible.builtin.apt_key", 1) + rows_for("ansible.builtin.copy", 20)

      sample = StratifiedSample.take(rows, 6, by: :module_fqcn)

      fqcns = sample.map { |r| r[:module_fqcn] }
      assert_includes fqcns, "ansible.builtin.apt_key"
      assert_includes fqcns, "ansible.builtin.apt"
      assert_includes fqcns, "ansible.builtin.copy"
    end

    test "returns exactly the requested limit when enough rows exist" do
      rows = rows_for("a", 10) + rows_for("b", 10)

      sample = StratifiedSample.take(rows, 7, by: :module_fqcn)

      assert_equal 7, sample.size
    end

    test "returns all rows without raising when the limit exceeds total rows" do
      rows = rows_for("a", 2) + rows_for("b", 1)

      sample = StratifiedSample.take(rows, 100, by: :module_fqcn)

      assert_equal 3, sample.size
    end

    test "never returns duplicate rows" do
      rows = rows_for("a", 5) + rows_for("b", 5)

      sample = StratifiedSample.take(rows, 8, by: :module_fqcn)

      assert_equal sample.uniq.size, sample.size
    end
  end
end
