defmodule DiffCoverage.HtmlGeneratorTest do
  use ExUnit.Case, async: true

  alias DiffCoverage.HtmlGenerator

  describe "generate/2" do
    test "generates HTML with file information" do
      filtered_files = [
        %{
          path: "lib/foo.ex",
          lines: [
            %{
              line_number: 1,
              content: "defmodule Foo do",
              coverage: :not_executable,
              changed: true
            },
            %{line_number: 2, content: "  def bar, do: :ok", coverage: :covered, changed: true}
          ],
          stats: %{
            changed_lines: 1,
            covered_changed: 1,
            uncovered_changed: 0,
            coverage_percent: 100.0
          }
        }
      ]

      html = HtmlGenerator.generate(filtered_files)

      assert html =~ "lib/foo.ex"
      assert html =~ "defmodule Foo do"
      assert html =~ "def bar, do: :ok"
    end

    test "uses provided base branch in output" do
      filtered_files = [
        %{
          path: "lib/foo.ex",
          lines: [%{line_number: 1, content: "code", coverage: :covered, changed: true}],
          stats: %{
            changed_lines: 1,
            covered_changed: 1,
            uncovered_changed: 0,
            coverage_percent: 100.0
          }
        }
      ]

      html = HtmlGenerator.generate(filtered_files, base_branch: "develop")

      assert html =~ "develop"
    end

    test "shows empty state when no files" do
      html = HtmlGenerator.generate([])

      assert html =~ "No Changed Elixir Files"
    end

    test "includes coverage statistics" do
      filtered_files = [
        %{
          path: "lib/foo.ex",
          lines: [
            %{line_number: 1, content: "covered", coverage: :covered, changed: true},
            %{line_number: 2, content: "uncovered", coverage: :uncovered, changed: true}
          ],
          stats: %{
            changed_lines: 2,
            covered_changed: 1,
            uncovered_changed: 1,
            coverage_percent: 50.0
          }
        }
      ]

      html = HtmlGenerator.generate(filtered_files)

      assert html =~ "50"
      assert html =~ "1 covered"
      assert html =~ "1 uncovered"
    end

    test "uses provided :stats over stats computed from the displayed files" do
      filtered_files = [
        %{
          path: "lib/foo.ex",
          lines: [%{line_number: 1, content: "x", coverage: :uncovered, changed: true}],
          stats: %{
            changed_lines: 1,
            covered_changed: 0,
            uncovered_changed: 1,
            coverage_percent: 0.0
          }
        }
      ]

      overall = %{
        total_changed: 10,
        total_covered: 9,
        total_uncovered: 1,
        coverage_percent: 90.0
      }

      html = HtmlGenerator.generate(filtered_files, stats: overall)

      assert html =~ "90.0%"
    end
  end

  describe "write_report/3" do
    @tag :tmp_dir
    test "writes HTML to file", %{tmp_dir: tmp_dir} do
      output_path = Path.join(tmp_dir, "report.html")

      filtered_files = [
        %{
          path: "lib/foo.ex",
          lines: [%{line_number: 1, content: "code", coverage: :covered, changed: true}],
          stats: %{
            changed_lines: 1,
            covered_changed: 1,
            uncovered_changed: 0,
            coverage_percent: 100.0
          }
        }
      ]

      assert :ok = HtmlGenerator.write_report(filtered_files, output_path)
      assert File.exists?(output_path)
      assert File.read!(output_path) =~ "lib/foo.ex"
    end

    @tag :tmp_dir
    test "creates parent directories if needed", %{tmp_dir: tmp_dir} do
      output_path = Path.join([tmp_dir, "nested", "dir", "report.html"])

      assert :ok = HtmlGenerator.write_report([], output_path)
      assert File.exists?(output_path)
    end
  end

  describe "render_lines/1" do
    test "renders contiguous lines without gaps" do
      lines = [
        %{line_number: 1, content: "line1", coverage: :covered, changed: true},
        %{line_number: 2, content: "line2", coverage: :covered, changed: true},
        %{line_number: 3, content: "line3", coverage: :covered, changed: true}
      ]

      html = HtmlGenerator.render_lines(lines)

      assert html =~ "line1"
      assert html =~ "line2"
      assert html =~ "line3"
      refute html =~ "gap"
    end

    test "renders gap indicator between non-contiguous line chunks" do
      lines = [
        %{line_number: 1, content: "line1", coverage: :covered, changed: true},
        %{line_number: 10, content: "line10", coverage: :covered, changed: true}
      ]

      html = HtmlGenerator.render_lines(lines)

      assert html =~ "line1"
      assert html =~ "line10"
      assert html =~ "gap"
      assert html =~ "Lines 2-9 (8 lines)"
    end

    test "renders single line gap indicator" do
      lines = [
        %{line_number: 1, content: "line1", coverage: :covered, changed: true},
        %{line_number: 3, content: "line3", coverage: :covered, changed: true}
      ]

      html = HtmlGenerator.render_lines(lines)

      assert html =~ "Line 2 hidden"
    end

    test "renders multiple gap indicators for multiple chunks" do
      lines = [
        %{line_number: 1, content: "line1", coverage: :covered, changed: true},
        %{line_number: 5, content: "line5", coverage: :covered, changed: true},
        %{line_number: 10, content: "line10", coverage: :covered, changed: true}
      ]

      html = HtmlGenerator.render_lines(lines)

      assert html =~ "Lines 2-4 (3 lines)"
      assert html =~ "Lines 6-9 (4 lines)"
    end

    test "applies correct CSS classes for coverage status" do
      lines = [
        %{line_number: 1, content: "covered", coverage: :covered, changed: true},
        %{line_number: 2, content: "uncovered", coverage: :uncovered, changed: true},
        %{line_number: 3, content: "not_exec", coverage: :not_executable, changed: true},
        %{line_number: 4, content: "context", coverage: :covered, changed: false}
      ]

      html = HtmlGenerator.render_lines(lines)

      assert html =~ ~r/class="changed covered"/
      assert html =~ ~r/class="changed uncovered"/
      assert html =~ ~r/class="changed not-executable"/
      assert html =~ ~r/class="context covered"/
    end

    test "escapes HTML special characters in content" do
      lines = [
        %{
          line_number: 1,
          content: "<script>alert('xss')</script>",
          coverage: :covered,
          changed: true
        },
        %{line_number: 2, content: "a && b", coverage: :covered, changed: true},
        %{line_number: 3, content: ~s(attr="value"), coverage: :covered, changed: true}
      ]

      html = HtmlGenerator.render_lines(lines)

      assert html =~ "&lt;script&gt;"
      assert html =~ "&amp;&amp;"
      assert html =~ "&quot;value&quot;"
      refute html =~ "<script>"
    end

    test "handles empty lines list" do
      assert "" = HtmlGenerator.render_lines([])
    end
  end
end
