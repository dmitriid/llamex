defmodule Llamex.Check.NoSelfInLiveViews do
  @moduledoc """
  Finds `self()` calls in Phoenix LiveView modules.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [skip_tests: true],
    explanations: [
      check: """
      LiveView has async assigns for work that must run after mount or events.
      A direct `self()` call in a LiveView often sends messages to the LiveView
      process from code that can use `assign_async/3`, `start_async/3`, or a
      supervised task.

      Use `start_async/3` or `assign_async/3`. Handle the result with built-in
      Phoenix functions. Use `Task` or supervisor trees only in rare cases.
      """,
      params: [
        skip_tests:
          "When true, files under `test/`, `*_test.exs` files, and files under `lib/mix/tasks/` are skipped."
      ]
    ]

  alias Credo.IssueMeta
  alias Llamex.Analysis.{AST, Source}

  @message "Do not use self() in Phoenix LiveViews. Use start_async/3 or assign_async/3, and handle the result with built-in Phoenix functions. Use Task or supervisor trees only in rare cases."

  @impl true
  def run(source_file, params \\ []) do
    if Source.skip_tests?(source_file, params, __MODULE__) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> AST.ast()
      |> AST.walk_with_ancestors(&self_issue(&1, &2, issue_meta))
    end
  end

  defp self_issue(node, ancestors, issue_meta) do
    case AST.call_identity(node) do
      %{module: nil, function: :self, arity: 0, line: line, trigger: trigger} ->
        if live_view_context?(ancestors) do
          format_issue(issue_meta,
            message: @message,
            trigger: trigger,
            line_no: line
          )
        end

      _ ->
        nil
    end
  end

  defp live_view_context?(ancestors) do
    case Enum.find_value(ancestors, &module_body/1) do
      nil -> false
      body -> live_view_body?(body)
    end
  end

  defp module_body({:defmodule, _meta, [_module, [do: body]]}), do: body
  defp module_body(_node), do: nil

  defp live_view_body?(body) do
    body
    |> AST.module_use_calls()
    |> Enum.any?(&live_view_use?/1)
  end

  defp live_view_use?(%{module: Phoenix.LiveView}), do: true
  defp live_view_use?(%{args: [:live_view | _args]}), do: true
  defp live_view_use?(_use_call), do: false
end
