defmodule DiffCoverage.CoverageFilter do
  @moduledoc """
  Filters ExCoveralls JSON coverage data to only include changed lines.
  """

  @typedoc "A line with coverage info and change status"
  @type line_info :: %{
          line_number: pos_integer(),
          content: String.t(),
          coverage: :covered | :uncovered | :not_executable,
          changed: boolean()
        }

  @typedoc "A filtered file with coverage data"
  @type filtered_file :: %{
          path: String.t(),
          lines: [line_info()],
          stats: %{
            changed_lines: non_neg_integer(),
            covered_changed: non_neg_integer(),
            uncovered_changed: non_neg_integer(),
            coverage_percent: float()
          }
        }

  @doc """
  Filters coverage data to focus on changed lines.

  Takes the parsed ExCoveralls JSON coverage data and a map of changed line ranges,
  and returns filtered coverage information highlighting the changed lines.

  ## Options

  - `:context_lines` - Number of unchanged lines to include around changed regions (default: 3)
  - `:skip_files` - List of file path patterns to skip

  ## Examples

      iex> coverage_data = %{"source_files" => [
      ...>   %{"name" => "lib/foo.ex", "source" => "defmodule Foo do\\n  def bar, do: :ok\\nend", "coverage" => [nil, 1, nil]}
      ...> ]}
      iex> changes = %{"lib/foo.ex" => [{2, 2}]}
      iex> DiffCoverage.CoverageFilter.filter(coverage_data, changes)
      [%{path: "lib/foo.ex", lines: [...], stats: %{...}}]

  """
  @spec filter(map(), map(), keyword()) :: [filtered_file()]
  def filter(coverage_data, changes, options \\ []) do
    context_lines = Keyword.get(options, :context_lines, 3)
    skip_files = Keyword.get(options, :skip_files, [])

    coverage_data
    |> Map.get("source_files", [])
    |> Enum.filter(&file_has_changes?(&1, changes))
    |> Enum.reject(&skip_file?(&1, skip_files))
    |> Enum.map(&filter_file(&1, changes, context_lines))
    |> Enum.sort_by(& &1.stats.uncovered_changed, :desc)
  end

  @doc """
  Rejects files whose changed lines are fully covered.

  Keeps only files with at least one uncovered changed line, so a report can
  focus on changes that still need tests. Files with no executable changed lines
  count as fully covered and are also rejected.
  """
  @spec reject_fully_covered([filtered_file()]) :: [filtered_file()]
  def reject_fully_covered(filtered_files) do
    Enum.reject(filtered_files, &(&1.stats.uncovered_changed == 0))
  end

  @typedoc "Information about skipped files"
  @type skipped_info :: %{
          files: [String.t()],
          lines: non_neg_integer()
        }

  @doc """
  Returns information about changed files that were skipped due to skip patterns,
  including the list of file paths and total count of skipped changed lines.
  """
  @spec find_skipped(map(), map(), [String.t()]) :: skipped_info()
  def find_skipped(coverage_data, changes, skip_patterns) do
    skipped_files =
      coverage_data
      |> Map.get("source_files", [])
      |> Enum.filter(&file_has_changes?(&1, changes))
      |> Enum.filter(&skip_file?(&1, skip_patterns))

    files = skipped_files |> Enum.map(& &1["name"]) |> Enum.sort()

    lines =
      skipped_files
      |> Enum.map(fn source_file ->
        path = source_file["name"]
        coverage = source_file["coverage"]
        changed_ranges = Map.get(changes, path, [])

        coverage
        |> Enum.with_index(1)
        |> Enum.count(fn {cov, line_number} ->
          cov != nil and line_in_ranges?(line_number, changed_ranges)
        end)
      end)
      |> Enum.sum()

    %{files: files, lines: lines}
  end

  @doc """
  Calculates aggregate statistics for all filtered files.
  """
  @spec aggregate_stats([filtered_file()]) :: %{
          total_changed: non_neg_integer(),
          total_covered: non_neg_integer(),
          total_uncovered: non_neg_integer(),
          coverage_percent: float()
        }
  def aggregate_stats(filtered_files) do
    stats =
      Enum.reduce(filtered_files, %{changed: 0, covered: 0, uncovered: 0}, fn file, acc ->
        %{
          changed: acc.changed + file.stats.changed_lines,
          covered: acc.covered + file.stats.covered_changed,
          uncovered: acc.uncovered + file.stats.uncovered_changed
        }
      end)

    coverage_percent =
      if stats.changed > 0 do
        Float.round(stats.covered / stats.changed * 100, 1)
      else
        100.0
      end

    %{
      total_changed: stats.changed,
      total_covered: stats.covered,
      total_uncovered: stats.uncovered,
      coverage_percent: coverage_percent
    }
  end

  @doc """
  Calculates overall coverage statistics from the full coverage data.
  Returns the total percentage of executable lines covered across all files.
  """
  @spec overall_coverage(map()) :: %{
          total_lines: non_neg_integer(),
          covered_lines: non_neg_integer(),
          coverage_percent: float()
        }
  def overall_coverage(coverage_data) do
    stats =
      coverage_data
      |> Map.get("source_files", [])
      |> Enum.reduce(%{total: 0, covered: 0}, fn source_file, acc ->
        coverage = source_file["coverage"] || []

        file_stats =
          Enum.reduce(coverage, %{total: 0, covered: 0}, fn cov, file_acc ->
            case cov do
              nil ->
                file_acc

              0 ->
                %{file_acc | total: file_acc.total + 1}

              n when is_integer(n) and n > 0 ->
                %{total: file_acc.total + 1, covered: file_acc.covered + 1}
            end
          end)

        %{
          total: acc.total + file_stats.total,
          covered: acc.covered + file_stats.covered
        }
      end)

    coverage_percent =
      if stats.total > 0 do
        Float.round(stats.covered / stats.total * 100, 1)
      else
        100.0
      end

    %{
      total_lines: stats.total,
      covered_lines: stats.covered,
      coverage_percent: coverage_percent
    }
  end

  defp file_has_changes?(source_file, changes) do
    Map.has_key?(changes, source_file["name"])
  end

  defp skip_file?(source_file, skip_patterns) do
    file_name = source_file["name"]

    Enum.any?(skip_patterns, fn pattern ->
      String.starts_with?(file_name, pattern) or String.contains?(file_name, pattern)
    end)
  end

  defp filter_file(source_file, changes, context_lines) do
    path = source_file["name"]
    source = source_file["source"]
    coverage = source_file["coverage"]
    changed_ranges = Map.get(changes, path, [])

    source_lines = String.split(source, "\n")

    lines =
      source_lines
      |> Enum.zip(coverage)
      |> Enum.with_index(1)
      |> Enum.map(fn {{content, cov}, line_number} ->
        %{
          line_number: line_number,
          content: content,
          coverage: coverage_status(cov),
          changed: line_in_ranges?(line_number, changed_ranges)
        }
      end)

    lines_to_show = calculate_lines_to_show(lines, changed_ranges, context_lines)

    filtered_lines = Enum.filter(lines, fn line -> line.line_number in lines_to_show end)

    stats = calculate_file_stats(lines)

    %{
      path: path,
      lines: filtered_lines,
      stats: stats
    }
  end

  defp coverage_status(nil), do: :not_executable
  defp coverage_status(0), do: :uncovered
  defp coverage_status(n) when is_integer(n) and n > 0, do: :covered

  defp line_in_ranges?(line_number, ranges) do
    Enum.any?(ranges, fn {start_line, end_line} ->
      line_number >= start_line and line_number <= end_line
    end)
  end

  defp calculate_lines_to_show(lines, changed_ranges, context_lines) do
    max_line = length(lines)

    changed_ranges
    |> Enum.flat_map(fn {start_line, end_line} ->
      context_start = max(1, start_line - context_lines)
      context_end = min(max_line, end_line + context_lines)
      Enum.to_list(context_start..context_end)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp calculate_file_stats(lines) do
    changed_lines = Enum.filter(lines, & &1.changed)
    executable_changed = Enum.filter(changed_lines, &(&1.coverage != :not_executable))

    covered_changed = Enum.count(executable_changed, &(&1.coverage == :covered))
    uncovered_changed = Enum.count(executable_changed, &(&1.coverage == :uncovered))

    total_executable_changed = length(executable_changed)

    coverage_percent =
      if total_executable_changed > 0 do
        Float.round(covered_changed / total_executable_changed * 100, 1)
      else
        100.0
      end

    %{
      changed_lines: total_executable_changed,
      covered_changed: covered_changed,
      uncovered_changed: uncovered_changed,
      coverage_percent: coverage_percent
    }
  end
end
