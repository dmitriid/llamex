defmodule Llamex.Check.NoLLMismsInComments do
  @moduledoc """
  Finds comment blocks and doc strings with too much text that machines
  write and humans do not.
  """

  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    exit_status: 0,
    param_defaults: [skip_tests: true, max_llmisms: 2, window_lines: 10],
    explanations: [
      check: """
      A comment must read like text that a person wrote for another
      person. This check scans each `#` comment block and each doc
      string for phrases that language models write and people do not.
      The doc strings are the values of `@moduledoc`, `@doc`,
      `@typedoc`, and `@shortdoc`. It reports a block when the count of
      matches is above the limit for the block size.

      The default limit is 2 matches per 10 lines. The limit scales with
      the block size. One match in one line is above the limit.

      Write comments and docs with these rules:

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

      A comment states a constraint that the code cannot express. Delete
      a comment that describes what the code visibly does.

      This check reports a warning. It does not change the exit status.
      """,
      params: [
        skip_tests:
          "When true, files under `test/`, `*_test.exs` files, and files under `lib/mix/tasks/` are skipped.",
        max_llmisms: "The number of matches that a block of `window_lines` lines can contain.",
        window_lines: "The number of lines that `max_llmisms` applies to."
      ]
    ]

  alias Credo.Check.Params
  alias Credo.IssueMeta
  alias Llamex.Analysis.{Comments, Docs, Prose, Source}

  @message "Too many LLMisms and non-human text in"

  @impl true
  def run(source_file, params \\ []) do
    if Source.skip_tests?(source_file, params, __MODULE__) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      limit = %{
        max_llmisms: Params.get(params, :max_llmisms, __MODULE__),
        window_lines: Params.get(params, :window_lines, __MODULE__)
      }

      blocks =
        Enum.map(Comments.blocks(source_file), &{"comments", &1}) ++
          Enum.map(Docs.blocks(source_file), &{"docs", &1})

      Enum.flat_map(blocks, &block_issues(&1, limit, issue_meta))
    end
  end

  defp block_issues({kind, block}, limit, issue_meta) do
    scanned =
      Enum.map(block, &%{line: &1.line, findings: &1.text |> Prose.strip_noise() |> Prose.scan()})

    window_size = min(limit.window_lines, length(scanned))

    scanned
    |> Enum.chunk_every(window_size, 1, :discard)
    |> Enum.find_value([], &window_issue(&1, kind, limit, issue_meta))
  end

  # The limit is a ratio. A window of `size` lines can contain
  # `max_llmisms * size / window_lines` matches. Integer math keeps the
  # comparison exact.
  defp window_issue(window, kind, limit, issue_meta) do
    findings = Enum.flat_map(window, & &1.findings)
    size = length(window)

    if length(findings) * limit.window_lines > limit.max_llmisms * size do
      first_line = Enum.find(window, &(&1.findings != []))
      classes = findings |> Enum.map(& &1.class) |> Enum.uniq() |> Enum.join(", ")

      [
        format_issue(issue_meta,
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
