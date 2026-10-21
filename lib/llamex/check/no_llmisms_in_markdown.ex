defmodule Llamex.Check.NoLLMismsInMarkdown do
  @moduledoc """
  Finds Markdown sections with too much text that machines write and
  humans do not.
  """

  alias Llamex.Analysis.LLMisms

  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    exit_status: 0,
    param_defaults: [
      paths: ["**/*.md"],
      excluded_paths: ["deps/**", "_build/**", "cover/**", "tmp/**", "**/node_modules/**"],
      max_llmisms: 2,
      window_lines: 10
    ],
    explanations: [
      check: """
      A document must read like text that a person wrote for another
      person. This check scans the Markdown files of the project for
      phrases that language models write and people do not. Each
      heading starts a new section. The check reports a section when
      the count of matches is above the limit for the section size.

      The check does not scan code blocks, HTML blocks, or front matter.
      Glob patterns select the files. The patterns do not match files in
      hidden directories, for example `.github/`.

      The default limit is 2 matches per 10 lines. The limit scales with
      the section size. One match in one line is above the limit.

      Write Markdown text with these rules:

      #{LLMisms.writing_rules()}
      The check needs the `:mdex` package. Add `:mdex` to the
      dependencies of the project.

      The LLMism issues are readability issues. They do not change the
      exit status. A file that is not UTF-8 text gets an issue in the
      warning category. That issue changes the exit status.
      """,
      params: [
        paths: "The glob patterns of the Markdown files to scan.",
        excluded_paths: "The glob patterns of the Markdown files to skip.",
        max_llmisms: "The number of matches that a section of `window_lines` lines can contain.",
        window_lines: "The number of lines that `max_llmisms` applies to."
      ]
    ]

  alias Credo.Check.Params
  alias Credo.CLI.Output.UI
  alias Credo.IssueMeta
  alias Llamex.Analysis.Markdown

  # The Markdown files are not Credo source files. `Llamex.Credo.AddMarkdownFiles`
  # adds the files with issues to the source file list after the analysis.
  @impl true
  def run_on_all_source_files(exec, _source_files, params) do
    if Markdown.available?() do
      params
      |> markdown_files()
      |> Enum.flat_map(&file_issues(&1, params))
      |> append_issues_and_timings(exec)
    else
      UI.warn([
        :red,
        "** (llamex) #{inspect(__MODULE__)} needs the :mdex package. ",
        "Add {:mdex, \"~> 0.14\"} to the dependencies of the project."
      ])
    end

    :ok
  end

  @impl true
  def run(%SourceFile{} = source_file, params) do
    source_file
    |> SourceFile.source()
    |> Markdown.blocks()
    |> Enum.map(&{"markdown", &1})
    |> LLMisms.issues(params, IssueMeta.for(source_file, params), __MODULE__)
  end

  defp file_issues(path, params) do
    source = File.read!(path)

    if String.valid?(source) do
      run(SourceFile.parse(source, path), params)
    else
      [encoding_issue(path, source, params)]
    end
  end

  # The issue has no line number. Credo prints the source line of an issue
  # with a line number, and this line is not valid text.
  defp encoding_issue(path, source, params) do
    line = source |> String.split("\n") |> Enum.find_index(&(not String.valid?(&1)))
    issue_meta = IssueMeta.for(%SourceFile{filename: Path.relative_to_cwd(path)}, params)

    format_issue(issue_meta,
      message: "Markdown file is not UTF-8 text: line #{line + 1} has bytes that are not UTF-8",
      category: :warning,
      exit_status: :warning
    )
  end

  defp markdown_files(params) do
    excluded = params |> Params.get(:excluded_paths, __MODULE__) |> wildcard() |> MapSet.new()

    params
    |> Params.get(:paths, __MODULE__)
    |> wildcard()
    |> Enum.reject(&(&1 in excluded or not File.regular?(&1)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp wildcard(patterns), do: Enum.flat_map(patterns, &Path.wildcard/1)
end
