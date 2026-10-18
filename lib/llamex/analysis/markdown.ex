defmodule Llamex.Analysis.Markdown do
  @moduledoc """
  Extracts prose blocks from a Markdown text.

  Each heading starts a new block. The text before the first heading is
  one block. Each line in a block has the line number and the raw text
  of the line. Blank lines, code blocks, HTML blocks, and front matter
  are not part of a block.

  The `:mdex` package parses the text. It is an optional dependency of
  Llamex. Call `available?/0` before `blocks/1`.
  """

  # `:mdex` is optional. The node modules are atoms in this module, not
  # struct patterns, so this module compiles without `:mdex`.
  @compile {:no_warn_undefined, MDEx}

  @type line :: %{line: pos_integer(), text: String.t()}

  @extension [
    autolink: true,
    footnotes: true,
    front_matter_delimiter: "---",
    strikethrough: true,
    table: true,
    tasklist: true
  ]

  @skipped_nodes [MDEx.CodeBlock, MDEx.FrontMatter, MDEx.HtmlBlock]

  @doc "Returns true when the `:mdex` package is loaded."
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(MDEx)

  @doc "Returns the prose blocks of the text, in source order."
  @spec blocks(String.t()) :: [[line()]]
  def blocks(markdown) do
    document = MDEx.parse_document!(markdown, extension: @extension)
    skipped = document |> Enum.filter(&(&1.__struct__ in @skipped_nodes)) |> line_set()
    headings = document |> Enum.filter(&(&1.__struct__ == MDEx.Heading)) |> start_lines()

    markdown
    |> String.split(~r/\r?\n/)
    |> Enum.with_index(1)
    |> Enum.reject(fn {text, line} -> line in skipped or String.trim(text) == "" end)
    |> Enum.map(fn {text, line} -> %{line: line, text: text} end)
    |> Enum.chunk_while([], &chunk_section(&1, &2, headings), &{:cont, Enum.reverse(&1), []})
    |> Enum.reject(&(&1 == []))
  end

  # An end column of 0 points to the start of the line after the node.
  defp line_set(nodes) do
    for %{sourcepos: %{start: {first, _}, end: {last, column}}} <- nodes,
        last = if(column == 0, do: last - 1, else: last),
        line <- first..max(first, last)//1,
        into: MapSet.new(),
        do: line
  end

  defp start_lines(nodes) do
    MapSet.new(nodes, fn %{sourcepos: %{start: {line, _}}} -> line end)
  end

  defp chunk_section(line, [], _headings), do: {:cont, [line]}

  defp chunk_section(line, acc, headings) do
    if line.line in headings do
      {:cont, Enum.reverse(acc), [line]}
    else
      {:cont, [line | acc]}
    end
  end
end
