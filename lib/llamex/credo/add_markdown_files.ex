defmodule Llamex.Credo.AddMarkdownFiles do
  @moduledoc false

  # Credo prints the source line of an issue from the source file list.
  # Credo runs the checks in parallel, and each check reads the list
  # when it starts. A Markdown file in the list during the analysis
  # gets the Elixir checks. This task adds the Markdown files with
  # issues to the list after the analysis.

  use Credo.Execution.Task

  alias Credo.SourceFile
  alias Llamex.Check.NoLLMismsInMarkdown

  @impl true
  def call(exec, _opts) do
    source_files = Execution.get_source_files(exec)
    known = MapSet.new(source_files, & &1.filename)

    markdown_files =
      exec
      |> Execution.get_issues()
      |> Enum.filter(&(&1.check == NoLLMismsInMarkdown and &1.line_no != nil))
      |> Enum.map(& &1.filename)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in known))
      |> Enum.map(&SourceFile.parse(File.read!(&1), &1))

    Execution.put_source_files(exec, source_files ++ markdown_files)
  end
end
