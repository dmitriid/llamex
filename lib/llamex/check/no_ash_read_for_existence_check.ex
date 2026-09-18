defmodule Llamex.Check.NoAshReadForExistenceCheck do
  @moduledoc """
  Flags Ash reads that are only used to check whether any records exist.
  """

  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [skip_tests: true],
    explanations: [
      check: """
      Ash.read!/1 (or Ash.read/1) loads and decodes every matching record.
      Piping that result straight into `Enum.any?()` throws all of that work
      away just to answer a yes/no question — a telltale sign is an
      `Ash.Query.limit(1)` added right before the read, added only to cap how
      much gets loaded for a check that never needed the records at all.

      `Ash.exists?/1` asks the data layer the same question directly, without
      loading or decoding any records.

      Replace `query |> Ash.read!() |> Enum.any?()` with
      `query |> Ash.exists?()`, and drop any `Ash.Query.limit(1)` added only
      to support the existence check.
      """,
      params: [
        skip_tests:
          "When true, files under `test/`, `*_test.exs` files, and files under `lib/mix/tasks/` are skipped."
      ]
    ]

  alias Credo.IssueMeta
  alias Llamex.Analysis.{AST, Source}

  @message "Use Ash.exists?/1 instead of Ash.read!/1 followed by Enum.any?()"
  @read_functions [:read, :read!]

  @impl true
  def run(source_file, params \\ []) do
    if Source.skip_tests?(source_file, params, __MODULE__) do
      []
    else
      ast = AST.ast(source_file)
      issue_meta = IssueMeta.for(source_file, params)

      AST.walk(ast, &existence_check_issue(&1, issue_meta))
    end
  end

  defp existence_check_issue({:|>, _, [input, right]}, issue_meta) do
    if bare_any_call?(right) and ash_read?(input) do
      issue_for(right, issue_meta)
    end
  end

  defp existence_check_issue(_node, _issue_meta), do: nil

  defp bare_any_call?(node) do
    case AST.call_identity(node) do
      %{module: Enum, function: :any?, arity: 0} -> true
      _ -> false
    end
  end

  defp ash_read?({:|>, _, [_input, right]}), do: ash_read?(right)

  defp ash_read?(node) do
    case AST.call_identity(node) do
      %{module_name: "Ash", function: function} -> function in @read_functions
      _ -> false
    end
  end

  defp issue_for(node, issue_meta) do
    call = AST.call_identity(node)

    format_issue(issue_meta,
      message: @message,
      trigger: call && call.trigger,
      line_no: call && call.line
    )
  end
end
