defmodule Llamex.Analysis.Docs do
  @moduledoc """
  Extracts doc strings from a source file.

  The doc strings are the values of `@moduledoc`, `@doc`, `@typedoc`,
  and `@shortdoc`. Each string is one block. Each line in a block has
  the line number and the text of the line. Blank lines, fenced code
  lines, and indented code lines are not part of the block.
  """

  alias Credo.SourceFile

  @type line :: %{line: pos_integer(), text: String.t()}

  @attributes [:moduledoc, :doc, :typedoc, :shortdoc]

  @doc "Returns the doc string blocks of the file, in source order."
  @spec blocks(SourceFile.t()) :: [[line()]]
  def blocks(%SourceFile{} = source_file) do
    source_file
    |> SourceFile.source()
    |> doc_strings()
    |> Enum.map(&lines/1)
    |> Enum.reject(&(&1 == []))
  end

  # `SourceFile.ast/1` drops the line of a string literal. The literal
  # encoder keeps the line and the delimiter in the block metadata.
  defp doc_strings(source) do
    options = [literal_encoder: &{:ok, {:__block__, &2, [&1]}}, token_metadata: true]

    case Code.string_to_quoted(source, options) do
      {:ok, ast} -> collect(ast)
      {:error, _reason} -> []
    end
  end

  defp collect(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:@, _, [{name, _, [value]}]} = node, acc when name in @attributes ->
          {node, add_doc(acc, doc_string(value))}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp add_doc(acc, nil), do: acc
  defp add_doc(acc, doc), do: [doc | acc]

  defp doc_string({:__block__, meta, [text]}) when is_binary(text), do: {meta, text}

  defp doc_string({sigil, meta, [{:<<>>, _, [text]}, _modifiers]})
       when sigil in [:sigil_S, :sigil_s] and is_binary(text),
       do: {meta, text}

  defp doc_string(_value), do: nil

  # The text of a heredoc starts on the line after the opening delimiter.
  defp lines({meta, text}) do
    first_line = if meta[:delimiter] == ~s("""), do: meta[:line] + 1, else: meta[:line]

    text
    |> String.split("\n")
    |> Enum.with_index(first_line)
    |> Enum.map(fn {text, line} -> %{line: line, text: text} end)
    |> reject_code()
    |> Enum.reject(&(String.trim(&1.text) == ""))
  end

  defp reject_code(lines) do
    {kept, _in_fence} =
      Enum.reduce(lines, {[], false}, fn line, {kept, in_fence} ->
        cond do
          fence?(line.text) -> {kept, not in_fence}
          in_fence or indented_code?(line.text) -> {kept, in_fence}
          true -> {[line | kept], in_fence}
        end
      end)

    Enum.reverse(kept)
  end

  defp fence?(text), do: text =~ ~r/^\s*(?:```|~~~)/

  defp indented_code?(text), do: text =~ ~r/^(?: {4}|\t)/
end
