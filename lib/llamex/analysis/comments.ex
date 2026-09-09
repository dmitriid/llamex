defmodule Llamex.Analysis.Comments do
  @moduledoc """
  Extracts `#` comment blocks from a source file.

  A block is a run of comments on consecutive lines. Each line in a
  block has the line number and the comment text without the `#`
  marker.
  """

  alias Credo.SourceFile

  @type line :: %{line: pos_integer(), text: String.t()}

  @doc "Returns the comment blocks of the file, in source order."
  @spec blocks(SourceFile.t()) :: [[line()]]
  def blocks(%SourceFile{} = source_file) do
    source_file
    |> SourceFile.source()
    |> comments()
    |> Enum.reject(&credo_directive?/1)
    |> Enum.map(&%{line: &1.line, text: strip_marker(&1.text)})
    |> Enum.chunk_while([], &chunk_consecutive/2, &{:cont, Enum.reverse(&1), []})
    |> Enum.reject(&(&1 == []))
  end

  defp comments(source) do
    case Code.string_to_quoted_with_comments(source) do
      {:ok, _ast, comments} -> comments
      {:error, _reason} -> []
    end
  end

  defp credo_directive?(%{text: text}), do: text =~ ~r/^#\s*credo:/

  defp strip_marker(text), do: String.replace(text, ~r/^#+\s?/, "")

  defp chunk_consecutive(line, []), do: {:cont, [line]}

  defp chunk_consecutive(line, [%{line: previous} | _] = acc) when line.line == previous + 1 do
    {:cont, [line | acc]}
  end

  defp chunk_consecutive(line, acc), do: {:cont, Enum.reverse(acc), [line]}
end
