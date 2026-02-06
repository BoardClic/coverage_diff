defmodule DiffCoverage.DiffParserTest do
  use ExUnit.Case, async: true

  alias DiffCoverage.DiffParser

  describe "parse_diff/1" do
    test "parses single file with one hunk" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc123..def456 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10,0 +10,3 @@ defmodule Foo do
      +  def new_function do
      +    :ok
      +  end
      """

      assert %{"lib/foo.ex" => [{10, 12}]} = DiffParser.parse_diff(diff)
    end

    test "parses single file with multiple hunks" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc123..def456 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10,0 +10,3 @@ defmodule Foo do
      +  def first do
      +    :ok
      +  end
      @@ -50,0 +53,2 @@ defmodule Foo do
      +  def second do
      +  end
      """

      assert %{"lib/foo.ex" => [{10, 12}, {53, 54}]} = DiffParser.parse_diff(diff)
    end

    test "parses multiple files" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc123..def456 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10,0 +10,3 @@
      +  def first do
      +    :ok
      +  end
      diff --git a/lib/bar.ex b/lib/bar.ex
      index 111222..333444 100644
      --- a/lib/bar.ex
      +++ b/lib/bar.ex
      @@ -5,0 +5,1 @@
      +  @moduledoc false
      """

      result = DiffParser.parse_diff(diff)

      assert %{"lib/foo.ex" => [{10, 12}], "lib/bar.ex" => [{5, 5}]} = result
    end

    test "handles single line changes (no count in header)" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc123..def456 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10 +10 @@ defmodule Foo do
      -  old_line
      +  new_line
      """

      assert %{"lib/foo.ex" => [{10, 10}]} = DiffParser.parse_diff(diff)
    end

    test "skips pure deletions (new count of 0)" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc123..def456 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10,3 +9,0 @@ defmodule Foo do
      -  def deleted do
      -    :ok
      -  end
      """

      assert %{"lib/foo.ex" => []} = DiffParser.parse_diff(diff)
    end

    test "filters to only Elixir files" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc123..def456 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10,0 +10,1 @@
      +  :new_line
      diff --git a/assets/app.js b/assets/app.js
      index 111222..333444 100644
      --- a/assets/app.js
      +++ b/assets/app.js
      @@ -5,0 +5,1 @@
      +console.log("hi");
      diff --git a/test/foo_test.exs b/test/foo_test.exs
      index 555666..777888 100644
      --- a/test/foo_test.exs
      +++ b/test/foo_test.exs
      @@ -20,0 +20,1 @@
      +  :test_line
      """

      result = DiffParser.parse_diff(diff)

      assert Enum.sort(Map.keys(result)) == ["lib/foo.ex", "test/foo_test.exs"]
      refute Map.has_key?(result, "assets/app.js")
    end

    test "handles empty diff" do
      assert %{} = DiffParser.parse_diff("")
    end

    test "handles file with no changes (empty hunk)" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc123..def456 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      """

      assert %{"lib/foo.ex" => []} = DiffParser.parse_diff(diff)
    end

    test "ignores malformed hunk headers" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc123..def456 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ invalid hunk header @@
      +  some code
      @@ -10,0 +10,1 @@ valid hunk
      +  valid code
      """

      assert %{"lib/foo.ex" => [{10, 10}]} = DiffParser.parse_diff(diff)
    end

    test "handles hunk headers with omitted counts (single line changes)" do
      # When a hunk affects only one line, git may omit the count
      # @@ -10 +15,3 @@ means: old line 10 (count=1), new lines 15-17 (count=3)
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc123..def456 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10 +15,3 @@ defmodule Foo do
      +  def added do
      +    :ok
      +  end
      """

      assert %{"lib/foo.ex" => [{15, 17}]} = DiffParser.parse_diff(diff)
    end
  end

  describe "diff_stats/1 parsing" do
    # These tests verify the internal parsing logic used by diff_stats/1
    # by testing parse_diff which uses similar hunk parsing

    test "correctly counts additions when old count is omitted" do
      # This tests the fix for the bug where empty strings from regex groups
      # caused String.to_integer("") to crash
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc123..def456 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10 +10,5 @@ defmodule Foo do
      +  line1
      +  line2
      +  line3
      +  line4
      +  line5
      """

      # Should parse successfully without crashing
      result = DiffParser.parse_diff(diff)
      assert %{"lib/foo.ex" => [{10, 14}]} = result
    end

    test "correctly counts when both counts are omitted" do
      # @@ -10 +10 @@ means single line replaced with single line
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc123..def456 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10 +10 @@ defmodule Foo do
      -  old_line
      +  new_line
      """

      result = DiffParser.parse_diff(diff)
      assert %{"lib/foo.ex" => [{10, 10}]} = result
    end
  end
end
