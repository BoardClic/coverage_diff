defmodule DiffCoverage.CoverageFilterTest do
  use ExUnit.Case, async: true

  alias DiffCoverage.CoverageFilter

  describe "filter/3" do
    test "filters coverage to only changed files" do
      coverage_data = %{
        "source_files" => [
          %{
            "name" => "lib/changed.ex",
            "source" => "line1\nline2\nline3",
            "coverage" => [1, 0, nil]
          },
          %{
            "name" => "lib/unchanged.ex",
            "source" => "other\ncode",
            "coverage" => [1, 1]
          }
        ]
      }

      changes = %{"lib/changed.ex" => [{1, 2}]}

      result = CoverageFilter.filter(coverage_data, changes)

      assert [%{path: "lib/changed.ex"}] = result
    end

    test "marks lines as changed or context" do
      coverage_data = %{
        "source_files" => [
          %{
            "name" => "lib/foo.ex",
            "source" => "line1\nline2\nline3\nline4\nline5",
            "coverage" => [1, 1, 0, nil, 1]
          }
        ]
      }

      changes = %{"lib/foo.ex" => [{3, 3}]}

      [result] = CoverageFilter.filter(coverage_data, changes, context_lines: 1)

      changed_lines = Enum.filter(result.lines, & &1.changed)
      context_lines = Enum.reject(result.lines, & &1.changed)

      assert [%{line_number: 3, changed: true}] = changed_lines
      assert Enum.all?(context_lines, &(&1.changed == false))
    end

    test "correctly identifies coverage status" do
      coverage_data = %{
        "source_files" => [
          %{
            "name" => "lib/foo.ex",
            "source" => "covered\nuncovered\nnot_exec",
            "coverage" => [5, 0, nil]
          }
        ]
      }

      changes = %{"lib/foo.ex" => [{1, 3}]}

      [result] = CoverageFilter.filter(coverage_data, changes)

      assert %{line_number: 1, coverage: :covered} =
               Enum.find(result.lines, &(&1.line_number == 1))

      assert %{line_number: 2, coverage: :uncovered} =
               Enum.find(result.lines, &(&1.line_number == 2))

      assert %{line_number: 3, coverage: :not_executable} =
               Enum.find(result.lines, &(&1.line_number == 3))
    end

    test "includes context lines around changes" do
      coverage_data = %{
        "source_files" => [
          %{
            "name" => "lib/foo.ex",
            "source" => Enum.join(1..10, "\n"),
            "coverage" => List.duplicate(1, 10)
          }
        ]
      }

      changes = %{"lib/foo.ex" => [{5, 5}]}

      [result] = CoverageFilter.filter(coverage_data, changes, context_lines: 2)

      line_numbers = Enum.map(result.lines, & &1.line_number)

      assert line_numbers == [3, 4, 5, 6, 7]
    end

    test "calculates file stats for changed lines only" do
      coverage_data = %{
        "source_files" => [
          %{
            "name" => "lib/foo.ex",
            "source" => "a\nb\nc\nd\ne",
            "coverage" => [1, 0, nil, 1, 0]
          }
        ]
      }

      changes = %{"lib/foo.ex" => [{1, 3}]}

      [result] = CoverageFilter.filter(coverage_data, changes, context_lines: 0)

      assert %{
               changed_lines: 2,
               covered_changed: 1,
               uncovered_changed: 1,
               coverage_percent: 50.0
             } = result.stats
    end

    test "skips files matching skip patterns" do
      coverage_data = %{
        "source_files" => [
          %{"name" => "lib/foo.ex", "source" => "code", "coverage" => [1]},
          %{"name" => "lib/seeder/data.ex", "source" => "seed", "coverage" => [1]},
          %{"name" => "test/support/factory.ex", "source" => "factory", "coverage" => [1]}
        ]
      }

      changes = %{
        "lib/foo.ex" => [{1, 1}],
        "lib/seeder/data.ex" => [{1, 1}],
        "test/support/factory.ex" => [{1, 1}]
      }

      result =
        CoverageFilter.filter(coverage_data, changes,
          skip_files: ["lib/seeder/", "test/support/"]
        )

      assert [%{path: "lib/foo.ex"}] = result
    end

    test "sorts files by uncovered count descending" do
      coverage_data = %{
        "source_files" => [
          %{"name" => "lib/few.ex", "source" => "a\nb", "coverage" => [1, 0]},
          %{"name" => "lib/many.ex", "source" => "a\nb\nc", "coverage" => [0, 0, 0]},
          %{"name" => "lib/none.ex", "source" => "a", "coverage" => [1]}
        ]
      }

      changes = %{
        "lib/few.ex" => [{1, 2}],
        "lib/many.ex" => [{1, 3}],
        "lib/none.ex" => [{1, 1}]
      }

      result = CoverageFilter.filter(coverage_data, changes, context_lines: 0)

      paths = Enum.map(result, & &1.path)

      assert paths == ["lib/many.ex", "lib/few.ex", "lib/none.ex"]
    end

    test "returns empty list when no changes match coverage files" do
      coverage_data = %{
        "source_files" => [
          %{"name" => "lib/foo.ex", "source" => "code", "coverage" => [1]}
        ]
      }

      changes = %{"lib/other.ex" => [{1, 1}]}

      assert [] = CoverageFilter.filter(coverage_data, changes)
    end

    test "handles file with only non-executable changed lines" do
      coverage_data = %{
        "source_files" => [
          %{
            "name" => "lib/foo.ex",
            "source" => "defmodule Foo do\nend",
            "coverage" => [nil, nil]
          }
        ]
      }

      changes = %{"lib/foo.ex" => [{1, 2}]}

      [result] = CoverageFilter.filter(coverage_data, changes, context_lines: 0)

      assert %{
               changed_lines: 0,
               covered_changed: 0,
               uncovered_changed: 0,
               coverage_percent: 100.0
             } = result.stats
    end
  end

  describe "reject_fully_covered/1" do
    test "keeps only files with uncovered changed lines" do
      filtered_files = [
        %{path: "lib/gaps.ex", lines: [], stats: %{uncovered_changed: 2}},
        %{path: "lib/covered.ex", lines: [], stats: %{uncovered_changed: 0}},
        %{path: "lib/non_exec.ex", lines: [], stats: %{uncovered_changed: 0}}
      ]

      assert [%{path: "lib/gaps.ex"}] = CoverageFilter.reject_fully_covered(filtered_files)
    end

    test "returns empty list when every file is fully covered" do
      filtered_files = [%{path: "lib/covered.ex", lines: [], stats: %{uncovered_changed: 0}}]

      assert [] = CoverageFilter.reject_fully_covered(filtered_files)
    end
  end

  describe "aggregate_stats/1" do
    test "aggregates stats across all files" do
      filtered_files = [
        %{
          path: "lib/a.ex",
          lines: [],
          stats: %{
            changed_lines: 10,
            covered_changed: 8,
            uncovered_changed: 2,
            coverage_percent: 80.0
          }
        },
        %{
          path: "lib/b.ex",
          lines: [],
          stats: %{
            changed_lines: 5,
            covered_changed: 3,
            uncovered_changed: 2,
            coverage_percent: 60.0
          }
        }
      ]

      result = CoverageFilter.aggregate_stats(filtered_files)

      assert %{
               total_changed: 15,
               total_covered: 11,
               total_uncovered: 4,
               coverage_percent: 73.3
             } = result
    end

    test "returns 100% coverage when no changed lines" do
      assert %{coverage_percent: 100.0} = CoverageFilter.aggregate_stats([])
    end
  end

  describe "find_skipped/3" do
    test "returns changed files and line count that match skip patterns" do
      coverage_data = %{
        "source_files" => [
          %{"name" => "lib/foo.ex", "source" => "code", "coverage" => [1]},
          %{
            "name" => "lib/seeder/data.ex",
            "source" => "line1\nline2\nline3",
            "coverage" => [1, 0, nil]
          },
          %{"name" => "test/support/factory.ex", "source" => "factory", "coverage" => [1]},
          %{"name" => "lib/unchanged.ex", "source" => "other", "coverage" => [1]}
        ]
      }

      changes = %{
        "lib/foo.ex" => [{1, 1}],
        "lib/seeder/data.ex" => [{1, 3}],
        "test/support/factory.ex" => [{1, 1}]
      }

      skip_patterns = ["lib/seeder/", "test/support/"]

      result = CoverageFilter.find_skipped(coverage_data, changes, skip_patterns)

      assert result.files == ["lib/seeder/data.ex", "test/support/factory.ex"]
      # lib/seeder/data.ex has 2 executable changed lines (line 1 and 2, line 3 is nil)
      # test/support/factory.ex has 1 executable changed line
      assert result.lines == 3
    end

    test "returns empty when no files match skip patterns" do
      coverage_data = %{
        "source_files" => [
          %{"name" => "lib/foo.ex", "source" => "code", "coverage" => [1]}
        ]
      }

      changes = %{"lib/foo.ex" => [{1, 1}]}

      result = CoverageFilter.find_skipped(coverage_data, changes, ["lib/other/"])

      assert result.files == []
      assert result.lines == 0
    end

    test "returns empty when skip patterns is empty" do
      coverage_data = %{
        "source_files" => [
          %{"name" => "lib/foo.ex", "source" => "code", "coverage" => [1]}
        ]
      }

      changes = %{"lib/foo.ex" => [{1, 1}]}

      result = CoverageFilter.find_skipped(coverage_data, changes, [])

      assert result.files == []
      assert result.lines == 0
    end
  end
end
