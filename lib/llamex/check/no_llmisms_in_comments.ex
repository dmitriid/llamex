defmodule Llamex.Check.NoLLMismsInComments do
  @moduledoc """
  Finds comment blocks and doc strings with too much text that machines
  write and humans do not.
  """

  alias Llamex.Analysis.LLMisms

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

      #{LLMisms.writing_rules()}
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

  alias Credo.IssueMeta
  alias Llamex.Analysis.{Comments, Docs, Source}

  @impl true
  def run(source_file, params \\ []) do
    if Source.skip_tests?(source_file, params, __MODULE__) do
      []
    else
      blocks =
        Enum.map(Comments.blocks(source_file), &{"comments", &1}) ++
          Enum.map(Docs.blocks(source_file), &{"docs", &1})

      LLMisms.issues(blocks, params, IssueMeta.for(source_file, params), __MODULE__)
    end
  end
end
