defmodule DiffCoverage.HtmlGenerator do
  @moduledoc """
  Generates HTML reports for diff coverage analysis.
  """

  alias DiffCoverage.CoverageFilter

  require EEx

  @doc """
  Generates an HTML report from filtered coverage data.

  ## Options

  - `:base_branch` - The base branch used for comparison (for display purposes)
  - `:diff_stats` - Map with `:additions`, `:deletions`, and `:files` counts

  """
  @spec generate([CoverageFilter.filtered_file()], keyword()) :: String.t()
  def generate(filtered_files, options \\ []) do
    base_branch = Keyword.get(options, :base_branch, "main")
    diff_stats = Keyword.get(options, :diff_stats, %{additions: 0, deletions: 0, files: 0})
    skipped = Keyword.get(options, :skipped, %{files: [], lines: 0})
    aggregate_stats = CoverageFilter.aggregate_stats(filtered_files)

    EEx.eval_file(
      template_path(),
      files: filtered_files,
      stats: aggregate_stats,
      diff_stats: diff_stats,
      skipped: skipped,
      base_branch: base_branch,
      generated_at: DateTime.utc_now(),
      coverage_color: coverage_color(aggregate_stats.coverage_percent),
      file_id: &file_id/1,
      render_lines: &render_lines/1
    )
  end

  defp coverage_color(percent) when percent >= 80, do: "#22c55e"
  defp coverage_color(percent) when percent >= 50, do: "#eab308"
  defp coverage_color(_percent), do: "#ef4444"

  defp file_id(path) do
    String.replace(path, ~r/[^a-zA-Z0-9]/, "-")
  end

  @doc """
  Writes the generated HTML report to the specified path.
  """
  @spec write_report([CoverageFilter.filtered_file()], String.t(), keyword()) ::
          :ok | {:error, term()}
  def write_report(filtered_files, output_path, options \\ []) do
    html = generate(filtered_files, options)

    with :ok <- output_path |> Path.dirname() |> File.mkdir_p() do
      File.write(output_path, html)
    end
  end

  defp template_path do
    Path.join(__DIR__, "templates/diff_coverage.html.eex")
  end

  @doc false
  def render_lines(lines) do
    lines
    |> chunk_with_gaps()
    |> add_gap_markers()
    |> Enum.flat_map(fn
      {:gap, from_line, to_line} -> [gap_row(from_line, to_line)]
      {:chunk, chunk} -> Enum.map(chunk, &line_row/1)
    end)
    |> Enum.join("\n")
  end

  defp add_gap_markers([]), do: []

  defp add_gap_markers([first_chunk | rest]),
    do: [{:chunk, first_chunk} | add_gaps_between(first_chunk, rest)]

  defp add_gaps_between(_prev_chunk, []), do: []

  defp add_gaps_between(prev_chunk, [next_chunk | rest]) do
    prev_last_line = List.last(prev_chunk).line_number
    next_first_line = List.first(next_chunk).line_number

    [
      {:gap, prev_last_line + 1, next_first_line - 1},
      {:chunk, next_chunk}
      | add_gaps_between(next_chunk, rest)
    ]
  end

  defp chunk_with_gaps(lines) do
    Enum.chunk_while(
      lines,
      {nil, []},
      fn line, {prev_num, acc} ->
        if prev_num && line.line_number > prev_num + 1 do
          {:cont, Enum.reverse(acc), {line.line_number, [line]}}
        else
          {:cont, {line.line_number, [line | acc]}}
        end
      end,
      fn
        {_, []} -> {:cont, []}
        {_, acc} -> {:cont, Enum.reverse(acc), []}
      end
    )
  end

  defp line_row(line) do
    class = line_class(line)
    content = escape_html(line.content)

    """
    <tr class="#{class}">
      <td class="line-number">#{line.line_number}</td>
      <td class="line-status"></td>
      <td class="line-content">#{content}</td>
    </tr>
    """
  end

  defp gap_row(from_line, to_line) do
    lines_hidden = to_line - from_line + 1

    text =
      if lines_hidden == 1 do
        "Line #{from_line} hidden"
      else
        "Lines #{from_line}-#{to_line} (#{lines_hidden} lines)"
      end

    """
    <tr class="gap">
      <td colspan="3">⋮ #{text} ⋮</td>
    </tr>
    """
  end

  defp line_class(line) do
    base = if line.changed, do: "changed", else: "context"

    coverage =
      case line.coverage do
        :covered -> "covered"
        :uncovered -> "uncovered"
        :not_executable -> "not-executable"
      end

    "#{base} #{coverage}"
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
