defmodule Llamex.Analysis.LLMisms do
  @moduledoc """
  Applies the LLMism limit to blocks of text.

  The limit is a ratio: `max_llmisms` matches per `window_lines` lines.
  Each block gets one issue at most. The issue points to the first
  window of lines that goes above the limit.
  """

  alias Credo.Check.Params
  alias Llamex.Analysis.Prose

  @message "Too many LLMisms and non-human text in"

  @doc """
  Returns the writing rules as a Markdown list.

  The check explanations show this list.
  """
  @spec writing_rules() :: String.t()
  def writing_rules do
    """
    - Write short sentences. Put one fact or one instruction in each
      sentence.
    - Use the active voice.
    - Use simple tenses: present, past, future. Do not write "has
      been" or "have changed".
    - Do not use contractions. Write "do not", not "don't".
    - Do not use "should", "would", "could", "might", or "may". If the
      rule is required, write "must". If the rule is optional, delete
      the sentence.
    - Do not use words that carry no fact: simply, robust, seamless,
      elegant, leverage, powerful.
    - Do not use idioms, metaphors, or filler phrases: "under the
      hood", "worth noting", "keep in mind", "happy path", "guardrail".
    - Do not describe your own process: "let me", "now we", "I will".
    - Do not use em dashes or semicolons. Write two sentences.
    - Do not use "e.g.", "i.e.", "in order to", or "prior to". Write
      "for example", "that is", "to", or "before".
    - State the fact. Do not label a fix as honest, clean, clever, or
      real.
    - For sequences of actions, prefer lists over multiple short sentences
      in a row.
    - Do not use run-on sentences.
    - Do not write more than 25 words in a sentence or more than 6
      sentences in a paragraph.
    - Break a line where there is a pause. Do not end a line on "the",
      "of", "and", or a similar word.
    - Vary the length of sentences and paragraphs.
    - Do not write chat text: openers ("Sure"), closers ("hope this
      helps"), or the voice of a chat assistant ("as an AI").
    - Do not write about the change under review: "no longer", "for
      now", "this PR", "previously". Write that text in the pull
      request.
    - Do not quote an error message. Write what fails and why.
    - Do not use dramatic verbs: "blows up", "falls over". Write what
      happens: raises, hangs, returns nil.
    - Do not start a list item with a bold label or an emoji.
    """
  end

  @doc """
  Returns the issues of the blocks.

  Each block is a tuple of a kind and a list of lines. The kind is a
  word for the issue message, for example "comments" or "docs". The
  check module supplies the param defaults and formats the issues.
  """
  @spec issues([{String.t(), [Prose.line()]}], Keyword.t(), Credo.IssueMeta.t(), module()) ::
          [Credo.Issue.t()]
  def issues(blocks, params, issue_meta, check) do
    limit = %{
      max_llmisms: Params.get(params, :max_llmisms, check),
      window_lines: Params.get(params, :window_lines, check)
    }

    Enum.flat_map(blocks, &block_issues(&1, limit, issue_meta, check))
  end

  defp block_issues({kind, block}, limit, issue_meta, check) do
    shape = block |> Prose.shape() |> Enum.group_by(& &1.line, &Map.delete(&1, :line))

    scanned =
      Enum.map(block, fn line ->
        findings = line.text |> Prose.strip_noise() |> Prose.scan()
        %{line: line.line, findings: findings ++ Map.get(shape, line.line, [])}
      end)

    window_size = min(limit.window_lines, length(scanned))

    scanned
    |> Enum.chunk_every(window_size, 1, :discard)
    |> Enum.find_value([], &window_issue(&1, kind, limit, issue_meta, check))
  end

  # A window of `size` lines can contain `max_llmisms * size /
  # window_lines` matches. Integer math keeps the comparison exact.
  defp window_issue(window, kind, limit, issue_meta, check) do
    findings = Enum.flat_map(window, & &1.findings)
    size = length(window)

    if length(findings) * limit.window_lines > limit.max_llmisms * size do
      first_line = Enum.find(window, &(&1.findings != []))
      classes = findings |> Enum.map(& &1.class) |> Enum.uniq() |> Enum.join(", ")

      [
        check.format_issue(issue_meta,
          message:
            "#{@message} #{kind}: #{length(findings)} found in #{lines(size)}, limit #{limit.max_llmisms} per #{lines(limit.window_lines)} (#{classes})",
          trigger: hd(first_line.findings).match,
          line_no: first_line.line
        )
      ]
    end
  end

  defp lines(1), do: "1 line"
  defp lines(count), do: "#{count} lines"
end
