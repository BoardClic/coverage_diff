defmodule DiffCoverage.DiffParser do
  @moduledoc """
  Parses git diff output to extract changed line ranges per file.
  """

  @doc """
  Returns changed line ranges for each file in the diff between the base branch and HEAD.

  Uses `git diff --unified=0 base...HEAD` to get minimal diff output with hunk headers.

  ## Examples

      iex> DiffCoverage.DiffParser.changed_lines("main")
      {:ok, %{"lib/boardclic/accounts.ex" => [{10, 15}, {42, 50}]}}

  """
  @spec changed_lines(base_branch :: String.t()) ::
          {:ok, %{String.t() => [{pos_integer(), pos_integer()}]}} | {:error, term()}
  def changed_lines(base_branch) do
    resolved_base = resolve_base_ref(base_branch)

    case run_git_diff(resolved_base) do
      {:ok, diff_output} -> {:ok, parse_diff(diff_output)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_base_ref(base_branch) do
    remote_ref = "origin/#{base_branch}"

    case System.cmd("git", ["rev-parse", "--verify", remote_ref], stderr_to_stdout: true) do
      {_, 0} -> remote_ref
      _ -> base_branch
    end
  end

  defp run_git_diff(base_ref) do
    case System.cmd("git", ["diff", "--unified=0", "#{base_ref}...HEAD"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _code} -> {:error, error}
    end
  end

  @doc """
  Parses raw git diff output into a map of file paths to changed line ranges.

  Git diff hunk header format: `@@ -old_start,old_count +new_start,new_count @@`
  - Single line change: `@@ -42 +42 @@` (no count means count of 1)
  - Multi-line change: `@@ -42,3 +42,5 @@`
  - Pure addition: `@@ -42,0 +43,5 @@` (old count of 0)
  - Pure deletion: `@@ -42,5 +41,0 @@` (new count of 0, skip these)

  ## Examples

      iex> diff = \"\"\"
      ...> diff --git a/lib/foo.ex b/lib/foo.ex
      ...> index abc123..def456 100644
      ...> --- a/lib/foo.ex
      ...> +++ b/lib/foo.ex
      ...> @@ -10,3 +10,5 @@ defmodule Foo do
      ...> +  def new_function do
      ...> +    :ok
      ...> +  end
      ...> \"\"\"
      iex> DiffCoverage.DiffParser.parse_diff(diff)
      %{"lib/foo.ex" => [{10, 14}]}

  """
  @spec parse_diff(String.t()) :: %{String.t() => [{pos_integer(), pos_integer()}]}
  def parse_diff(diff_output) do
    diff_output
    |> String.split("\n")
    |> parse_lines(nil, %{})
    |> filter_elixir_files()
  end

  @doc """
  Returns diff statistics (additions, deletions, file count) for the diff between base branch and HEAD.
  """
  @spec diff_stats(base_branch :: String.t()) ::
          {:ok,
           %{additions: non_neg_integer(), deletions: non_neg_integer(), files: non_neg_integer()}}
          | {:error, term()}
  def diff_stats(base_branch) do
    resolved_base = resolve_base_ref(base_branch)

    case run_git_diff(resolved_base) do
      {:ok, diff_output} -> {:ok, parse_diff_stats(diff_output)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_diff_stats(diff_output) do
    diff_output
    |> String.split("\n")
    |> parse_stats_lines(%{additions: 0, deletions: 0, files: MapSet.new()})
    |> then(fn stats -> %{stats | files: MapSet.size(stats.files)} end)
  end

  defp parse_stats_lines([], acc), do: acc

  defp parse_stats_lines(["diff --git a/" <> rest | lines], acc) do
    file_path = extract_file_path(rest)

    if String.ends_with?(file_path, ".ex") or String.ends_with?(file_path, ".exs") do
      parse_stats_lines(lines, %{acc | files: MapSet.put(acc.files, file_path)})
    else
      parse_stats_lines(lines, acc)
    end
  end

  defp parse_stats_lines(["@@ " <> hunk_info | lines], acc) do
    case parse_hunk_header_full(hunk_info) do
      {:ok, {old_count, new_count}} ->
        acc = %{acc | additions: acc.additions + new_count, deletions: acc.deletions + old_count}
        parse_stats_lines(lines, acc)

      :error ->
        parse_stats_lines(lines, acc)
    end
  end

  defp parse_stats_lines([_ | lines], acc) do
    parse_stats_lines(lines, acc)
  end

  defp parse_lines([], _current_file, acc), do: acc

  defp parse_lines(["diff --git a/" <> rest | lines], _current_file, acc) do
    file_path = extract_file_path(rest)
    parse_lines(lines, file_path, Map.put_new(acc, file_path, []))
  end

  defp parse_lines(["@@ " <> hunk_info | lines], current_file, acc)
       when not is_nil(current_file) do
    case parse_hunk_header(hunk_info) do
      {:ok, {start_line, count}} when count > 0 ->
        end_line = start_line + count - 1
        range = {start_line, end_line}
        acc = Map.update!(acc, current_file, &[range | &1])
        parse_lines(lines, current_file, acc)

      _ ->
        parse_lines(lines, current_file, acc)
    end
  end

  defp parse_lines([_ | lines], current_file, acc) do
    parse_lines(lines, current_file, acc)
  end

  defp extract_file_path(rest) do
    rest
    |> String.split(" b/")
    |> List.last()
  end

  defp parse_hunk_header(hunk_info) do
    regex = ~r/^-\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/

    case Regex.run(regex, hunk_info) do
      [_, start_str] ->
        {:ok, {String.to_integer(start_str), 1}}

      [_, start_str, count_str] ->
        {:ok, {String.to_integer(start_str), String.to_integer(count_str)}}

      nil ->
        :error
    end
  end

  defp parse_hunk_header_full(hunk_info) do
    regex = ~r/^-(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/

    case Regex.run(regex, hunk_info) do
      [_, _old_start, old_count, _new_start, new_count] ->
        old = parse_count(old_count)
        new = parse_count(new_count)
        {:ok, {old, new}}

      [_, _old_start, old_count, _new_start] ->
        {:ok, {parse_count(old_count), 1}}

      nil ->
        :error
    end
  end

  defp parse_count(""), do: 1
  defp parse_count(str), do: String.to_integer(str)

  defp filter_elixir_files(changes) do
    for {path, ranges} <- changes,
        String.ends_with?(path, ".ex") or String.ends_with?(path, ".exs"),
        into: %{} do
      {path, Enum.reverse(ranges)}
    end
  end
end
