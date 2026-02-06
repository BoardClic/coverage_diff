defmodule Mix.Tasks.Coveralls.Diff do
  @shortdoc "Generates a coverage report for changed lines only"

  @moduledoc """
  Generates a coverage report showing only code changed in the current branch,
  making it easy to identify untested changes.

      $ mix coveralls.diff
      $ mix coveralls.diff --base develop
      $ mix coveralls.diff --output cover/my_report.html
      $ mix coveralls.diff -- --exclude integration

  ## Options

  - `--base` - Base branch to compare against (default: `main`)
  - `--output` - Output path for HTML report (default: `cover/diff_coverage.html`)
  - `--context` - Number of context lines around changes (default: 3)

  Any arguments after `--` are passed through to `mix coveralls.json`.

  ## Workflow

  1. Runs `mix coveralls.json` to generate coverage data
  2. Parses `cover/excoveralls.json`
  3. Gets git diff vs base branch
  4. Filters coverage to changed lines
  5. Generates HTML report
  6. Prints summary to console

  """

  use Mix.Task

  alias DiffCoverage.{CoverageFilter, DiffParser, HtmlGenerator}

  @coverage_json_path "cover/excoveralls.json"
  @default_output "cover/diff_coverage.html"
  @default_base "main"

  # coveralls-ignore-start
  @impl Mix.Task
  def run(args) do
    {our_args, passthrough_args} = split_on_separator(args)

    {options, _, _} =
      OptionParser.parse(our_args,
        strict: [base: :string, output: :string, context: :integer],
        aliases: [b: :base, o: :output, c: :context]
      )

    base_branch = Keyword.get(options, :base, @default_base)
    output_path = Keyword.get(options, :output, @default_output)
    context_lines = Keyword.get(options, :context, 3)

    Mix.shell().info([:cyan, "Running tests with coverage...", :reset])

    case run_coveralls_json(passthrough_args) do
      :ok ->
        Mix.shell().info([:cyan, "Analyzing coverage for changed files...", :reset])
        analyze_and_report(base_branch, output_path, context_lines)

      {:error, reason} ->
        Mix.shell().error("Failed to run coveralls: #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp split_on_separator(args) do
    case Enum.split_while(args, &(&1 != "--")) do
      {before, ["--" | after_separator]} -> {before, after_separator}
      {before, []} -> {before, []}
    end
  end

  defp run_coveralls_json(extra_args) do
    case Mix.Task.run("coveralls.json", extra_args) do
      _ -> :ok
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp analyze_and_report(base_branch, output_path, context_lines) do
    with {:ok, changes} <- DiffParser.changed_lines(base_branch),
         {:ok, diff_stats} <- DiffParser.diff_stats(base_branch),
         {:ok, coverage_data} <- read_coverage_json(),
         skip_patterns <- load_skip_files() do
      if map_size(changes) == 0 do
        Mix.shell().info([:yellow, "\nNo Elixir file changes found.", :reset])
        :ok
      else
        filtered_files =
          CoverageFilter.filter(coverage_data, changes,
            context_lines: context_lines,
            skip_files: skip_patterns
          )

        skipped = CoverageFilter.find_skipped(coverage_data, changes, skip_patterns)

        report_options = [
          base_branch: base_branch,
          diff_stats: diff_stats,
          skipped: skipped
        ]

        overall_stats = CoverageFilter.overall_coverage(coverage_data)

        case HtmlGenerator.write_report(filtered_files, output_path, report_options) do
          :ok ->
            print_summary(filtered_files, overall_stats, skipped, output_path)
            :ok

          {:error, reason} ->
            Mix.shell().error("Failed to write report: #{inspect(reason)}")
            exit({:shutdown, 1})
        end
      end
    else
      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp read_coverage_json do
    case File.read(@coverage_json_path) do
      {:ok, content} -> {:ok, Jason.decode!(content)}
      {:error, reason} -> {:error, "Could not read #{@coverage_json_path}: #{reason}"}
    end
  end

  defp load_skip_files do
    case File.read("coveralls.json") do
      {:ok, content} ->
        content
        |> Jason.decode!()
        |> Map.get("skip_files", [])

      {:error, _} ->
        []
    end
  end

  defp print_summary(filtered_files, overall_stats, skipped, output_path) do
    stats = CoverageFilter.aggregate_stats(filtered_files)

    Mix.shell().info("")

    Mix.shell().info([
      "Full coverage: #{overall_stats.coverage_percent}% (#{overall_stats.covered_lines}/#{overall_stats.total_lines} lines)"
    ])

    coverage_color =
      cond do
        stats.coverage_percent >= 80 -> :green
        stats.coverage_percent >= 50 -> :yellow
        true -> :red
      end

    Mix.shell().info([
      coverage_color,
      "Changed Lines Coverage: #{stats.coverage_percent}% (#{stats.total_covered}/#{stats.total_changed})",
      :reset
    ])

    uncovered_files = Enum.filter(filtered_files, &(&1.stats.uncovered_changed > 0))

    if uncovered_files != [] do
      Mix.shell().info("")
      Mix.shell().info([:yellow, "Uncovered changes:", :reset])

      Enum.each(uncovered_files, fn file ->
        file
        |> find_uncovered_line_ranges()
        |> Enum.each(&print_uncovered_range(file.path, &1))
      end)
    end

    if skipped.files != [] do
      Mix.shell().info("")

      Mix.shell().info([
        :light_black,
        "Skipped #{skipped.lines} line(s) in #{length(skipped.files)} file(s) per coveralls.json",
        :reset
      ])
    end

    Mix.shell().info("")
    Mix.shell().info([:cyan, "Report: #{output_path}", :reset])
  end

  defp print_uncovered_range(path, {start_line, end_line}) do
    line_desc =
      if start_line == end_line do
        "#{path}:#{start_line} (1 line)"
      else
        "#{path}:#{start_line}-#{end_line} (#{end_line - start_line + 1} lines)"
      end

    Mix.shell().info(["  ", :red, line_desc, :reset])
  end

  defp find_uncovered_line_ranges(file) do
    file.lines
    |> Enum.filter(&(&1.changed and &1.coverage == :uncovered))
    |> Enum.map(& &1.line_number)
    |> collapse_to_ranges()
  end

  defp collapse_to_ranges([]), do: []

  defp collapse_to_ranges(line_numbers) do
    line_numbers
    |> Enum.sort()
    |> Enum.chunk_while(
      nil,
      fn
        line, nil ->
          {:cont, {line, line}}

        line, {start, prev} when line == prev + 1 ->
          {:cont, {start, line}}

        line, range ->
          {:cont, range, {line, line}}
      end,
      fn range -> {:cont, range, nil} end
    )
  end

  # coveralls-ignore-stop
end
