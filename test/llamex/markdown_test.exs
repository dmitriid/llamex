defmodule Llamex.MarkdownTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  @sloppy """
  # Notes

  We simply leverage the digest to keep things robust.
  """

  test "the plugin option scans Markdown sections and Credo prints the issues", %{tmp_dir: dir} do
    write(dir, "docs/guide.md", """
    ---
    title: We should simply skip this
    ---
    # Clean

    The cache key is the file digest.
    A new digest starts a new download.

    ```elixir
    # This should simply be robust.
    ```

    <div>
    We should simply skip this too.
    </div>

    # Sloppy

    We simply leverage the digest to keep things robust.
    """)

    {issues, output} = run_credo(dir, llmisms_in_markdown: [paths: [Path.join(dir, "**/*.md")]])

    assert [issue] = issues
    assert issue.check == Llamex.Check.NoLLMismsInMarkdown
    assert issue.filename == Path.relative_to_cwd(Path.join(dir, "docs/guide.md"))
    assert issue.line_no == 19
    assert issue.trigger == "simply"
    assert issue.exit_status == 0

    assert issue.message ==
             "Too many LLMisms and non-human text in markdown: 3 found in 2 lines, limit 2 per 10 lines (word with no fact)"

    assert output =~ "We simply leverage the digest to keep things robust."
  end

  test "each heading starts a new section", %{tmp_dir: dir} do
    write(dir, "notes.md", """
    # One

    This should pass.

    # Two

    The cache key is the file digest.

    # Three

    This could pass.
    """)

    {issues, _output} = run_credo(dir, llmisms_in_markdown: [paths: [Path.join(dir, "*.md")]])

    assert [3, 11] == issues |> Enum.map(& &1.line_no) |> Enum.sort()
  end

  test "excluded paths are not scanned", %{tmp_dir: dir} do
    write(dir, "docs/notes.md", @sloppy)
    write(dir, "vendor/notes.md", @sloppy)

    {issues, _output} =
      run_credo(dir,
        llmisms_in_markdown: [
          paths: [Path.join(dir, "**/*.md")],
          excluded_paths: [Path.join(dir, "vendor/**")]
        ]
      )

    assert [issue] = issues
    assert issue.filename == Path.relative_to_cwd(Path.join(dir, "docs/notes.md"))
  end

  test "a file that is not UTF-8 text fails the Credo run", %{tmp_dir: dir} do
    write(dir, "binary.md", "# Title\n\n" <> <<255, 254>> <> "body\n")
    write(dir, "notes.md", @sloppy)

    {issues, output, exit_status} =
      run_credo_with_status(dir, llmisms_in_markdown: [paths: [Path.join(dir, "*.md")]])

    assert [encoding, llmisms] = Enum.sort_by(issues, & &1.filename)
    assert encoding.filename == Path.relative_to_cwd(Path.join(dir, "binary.md"))
    assert encoding.category == :warning
    assert encoding.line_no == nil

    assert encoding.message ==
             "Markdown file is not UTF-8 text: line 3 has bytes that are not UTF-8"

    assert llmisms.filename == Path.relative_to_cwd(Path.join(dir, "notes.md"))
    assert exit_status != 0
    assert output =~ "Markdown file is not UTF-8 text"
  end

  test "the check params change the limit", %{tmp_dir: dir} do
    write(dir, "notes.md", @sloppy)
    paths = [Path.join(dir, "*.md")]

    assert {[], _output} =
             run_credo(dir, llmisms_in_markdown: [paths: paths, max_llmisms: 3, window_lines: 2])
  end

  test "the plugin does not scan Markdown files without the option", %{tmp_dir: dir} do
    write(dir, "notes.md", @sloppy)

    assert {[], _output} = run_credo(dir, llmisms_in_comments: true)
  end

  defp write(dir, path, content) do
    path = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp run_credo(dir, plugin_opts) do
    {issues, output, _exit_status} = run_credo_with_status(dir, plugin_opts)
    {issues, output}
  end

  defp run_credo_with_status(dir, plugin_opts) do
    write(dir, "lib/sample.ex", """
    defmodule Sample do
      @moduledoc false
    end
    """)

    config = Path.join(dir, ".credo.exs")

    File.write!(
      config,
      inspect(%{
        configs: [
          %{
            name: "default",
            files: %{included: [Path.join(dir, "lib/")]},
            plugins: [{Llamex, plugin_opts}]
          }
        ]
      })
    )

    # Credo prints through its shell process. The capture device must
    # be the group leader of that process.
    shell = Process.whereis(Credo.CLI.Output.Shell)
    {:group_leader, shell_leader} = Process.info(shell, :group_leader)

    output =
      try do
        capture_io(fn ->
          Process.group_leader(shell, Process.group_leader())
          send(self(), {:exec, Credo.run(["--config-file", config, "--strict", "--verbose"])})
        end)
      after
        Process.group_leader(shell, shell_leader)
      end

    assert_received {:exec, exec}

    issues =
      exec
      |> Credo.Execution.get_issues()
      |> Enum.filter(&(&1.check in Keyword.values(Llamex.optional_checks())))

    {issues, output, Credo.Execution.get_exit_status(exec)}
  end
end
