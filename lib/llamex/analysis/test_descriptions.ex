defmodule Llamex.Analysis.TestDescriptions do
  @moduledoc """
  Extracts test descriptions from a source file.

  The test descriptions are the string arguments of `describe`, `test`,
  and `property` calls. Each description is one block. Each line in a
  block has the line number and the text of the line. An interpolation
  becomes inline code, so the scan ignores it and the shape checks
  count it as one word.
  """

  alias Credo.SourceFile

  @type line :: %{line: pos_integer(), text: String.t()}

  @calls [:describe, :test, :property]

  @doc "Returns the test description blocks of the file, in source order."
  @spec blocks(SourceFile.t()) :: [[line()]]
  def blocks(%SourceFile{} = source_file) do
    source_file
    |> SourceFile.source()
    |> descriptions()
    |> Enum.map(&lines/1)
    |> Enum.reject(&(&1 == []))
  end

  # `SourceFile.ast/1` drops the line of a string literal. The literal
  # encoder keeps the line and the delimiter in the block metadata.
  defp descriptions(source) do
    options = [literal_encoder: &{:ok, {:__block__, &2, [&1]}}, token_metadata: true]

    case Code.string_to_quoted(source, options) do
      {:ok, ast} -> collect(ast)
      {:error, _reason} -> []
    end
  end

  defp collect(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {name, _, [value | _]} = node, acc when name in @calls ->
          {node, add_description(acc, description(value))}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp add_description(acc, nil), do: acc
  defp add_description(acc, description), do: [description | acc]

  defp description({:__block__, meta, [text]}) when is_binary(text), do: {meta, text}
  defp description({:<<>>, meta, parts}), do: {meta, Enum.map_join(parts, &part_text/1)}

  defp description({sigil, meta, [{:<<>>, _, parts}, _modifiers]})
       when sigil in [:sigil_S, :sigil_s],
       do: {meta, Enum.map_join(parts, &part_text/1)}

  defp description(_value), do: nil

  defp part_text(text) when is_binary(text), do: text
  defp part_text(_interpolation), do: "`code`"

  # The text of a heredoc starts on the line after the opening delimiter.
  defp lines({meta, text}) do
    first_line = if meta[:delimiter] == ~s("""), do: meta[:line] + 1, else: meta[:line]

    text
    |> String.split("\n")
    |> Enum.with_index(first_line)
    |> Enum.map(fn {text, line} -> %{line: line, text: text} end)
    |> Enum.reject(&(String.trim(&1.text) == ""))
  end
end
