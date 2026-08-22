defmodule Llamex.Check.NoMultipleAssigns do
  @moduledoc """
  Finds pipe chains with more than three single-key `assign` calls.
  """

  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    exit_status: 0,
    param_defaults: [skip_tests: true, max_assigns: 3],
    explanations: [
      check: """
      A long chain of single-key `assign` calls is hard to read. One
      `assign` call with a keyword list shows all keys in one place.

      Replace the chain:

          socket
          |> assign(:tab, tab)
          |> assign(:page, page)
          |> assign(:status, status)
          |> assign(:filter, filter)

      with one call:

          assign(socket,
            tab: tab,
            page: page,
            status: status,
            filter: filter
          )

      This check reports a warning. It does not change the exit status.
      """,
      params: [
        skip_tests:
          "When true, files under `test/`, `*_test.exs` files, and files under `lib/mix/tasks/` are skipped.",
        max_assigns: "The maximum number of single-key assign calls in one pipe chain."
      ]
    ]

  alias Credo.Check.Params
  alias Credo.IssueMeta
  alias Llamex.Analysis.{AST, Source}

  @message "For readability, avoid multiple assign statements. Use socket |> assign(key1: ..., key2: ...)"

  @impl true
  def run(source_file, params \\ []) do
    if Source.skip_tests?(source_file, params, __MODULE__) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      max_assigns = Params.get(params, :max_assigns, __MODULE__)

      source_file
      |> AST.ast()
      |> AST.walk_with_ancestors(&pipe_issue(&1, &2, max_assigns, issue_meta))
    end
  end

  defp pipe_issue({:|>, _, _}, [parent | _], _max_assigns, _issue_meta)
       when elem(parent, 0) == :|> do
    nil
  end

  defp pipe_issue({:|>, _, _} = node, _ancestors, max_assigns, issue_meta) do
    assigns =
      node
      |> pipe_stages()
      |> Enum.filter(&single_key_assign?/1)

    if length(assigns) > max_assigns do
      %{line: line, trigger: trigger} = AST.call_identity(hd(assigns))

      format_issue(issue_meta,
        message: @message,
        trigger: trigger,
        line_no: line
      )
    end
  end

  defp pipe_issue(_node, _ancestors, _max_assigns, _issue_meta), do: nil

  defp pipe_stages({:|>, _, [input, right]}), do: pipe_stages(input) ++ [right]
  defp pipe_stages(other), do: [other]

  # The chain head can hold a full assign(socket, key, value) call, so
  # arity 3 counts there. Piped stages hold assign(key, value) at arity 2.
  defp single_key_assign?(node) do
    case AST.call_identity(node) do
      %{function: :assign, arity: arity, args: args} when arity in [2, 3] ->
        not keyword_or_map_argument?(List.last(args))

      _ ->
        false
    end
  end

  defp keyword_or_map_argument?([{_key, _value} | _rest]), do: true
  defp keyword_or_map_argument?({:%{}, _, _}), do: true
  defp keyword_or_map_argument?(_argument), do: false
end
