defmodule Llamex.Check.NoOneLiners do
  @moduledoc """
  Flags redundant wrapper functions that only delegate or wrap a delegated result.
  """

  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    param_defaults: [skip_tests: true],
    explanations: [
      check: """
      Mechanical refactors often leave behind functions that add a name but no
      behavior. These wrappers make call graphs harder to read and give future
      readers a false signal that a boundary, policy, or translation exists.

      This check flags functions whose body only delegates to another call,
      assigns a delegated result and returns it, or ignores a helper result before
      returning a synthetic success tuple.

      Keep the wrapper when it changes behavior: guards or meaningful pattern
      matching, rescue/catch/after handling, validation, authorization,
      instrumentation, logging, or boundary callback shapes such as `handle_*`.
      Otherwise replace callers with the direct call or move real behavior into
      the wrapper.

      Functions marked with `@impl` are skipped because callback adapters and
      dependency-injection boundaries often intentionally keep thin forwarding
      functions. For rare non-callback exceptions, place
      `@llamex_one_liner_allowed true` immediately before the function.
      """,
      params: [
        skip_tests:
          "When true, files under `test/`, `*_test.exs` files, and files under `lib/mix/tasks/` are skipped."
      ]
    ]

  alias Credo.IssueMeta
  alias Llamex.Analysis.{AST, Source}

  @message "Redundant one-line wrapper. Replace with direct call"
  @non_delegating_calls [
    :if,
    :case,
    :cond,
    :with,
    :try,
    :receive,
    :for,
    :fn,
    :<<>>,
    :%,
    :%{},
    :&,
    :.,
    :"::",
    :|>,
    :__aliases__,
    :{},
    :=,
    :and,
    :or,
    :not,
    :!,
    :==,
    :===,
    :!=,
    :!==,
    :<,
    :>,
    :<=,
    :>=,
    :+,
    :-,
    :*,
    :/,
    :in
  ]

  @impl true
  def run(source_file, params \\ []) do
    if Source.skip_tests?(source_file, params, __MODULE__) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      ast = AST.ast(source_file)
      functions = AST.functions(ast)
      multi_clause_functions = multi_clause_functions(functions)
      allowed_function_lines = allowed_function_lines(ast)

      functions
      |> Enum.reject(
        &(multi_clause_function?(&1, multi_clause_functions) or
            MapSet.member?(allowed_function_lines, &1.line))
      )
      |> Enum.filter(&redundant_wrapper?(&1, source_file))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp allowed_function_lines(ast) do
    ast
    |> markers()
    |> Enum.sort_by(fn {_type, line, _value} -> line end)
    |> Enum.reduce({false, []}, fn
      {:attribute, _line, true}, {_pending, allowed_lines} ->
        {true, allowed_lines}

      {:attribute, _line, false}, {_pending, allowed_lines} ->
        {false, allowed_lines}

      {:function, line, _value}, {true, allowed_lines} ->
        {false, [line | allowed_lines]}

      {:function, _line, _value}, {_pending, allowed_lines} ->
        {false, allowed_lines}
    end)
    |> elem(1)
    |> MapSet.new()
  end

  defp markers(ast) do
    AST.walk(ast, fn
      {:@, meta, [{:impl, _, _values}]} ->
        {:attribute, meta[:line], true}

      {:@, meta, [{:llamex_one_liner_allowed, _, [true]}]} ->
        {:attribute, meta[:line], true}

      {:@, meta, [{:llamex_one_liner_allowed, _, [_value]}]} ->
        {:attribute, meta[:line], false}

      {:def, meta, _args} ->
        {:function, meta[:line], true}

      {:defp, meta, _args} ->
        {:function, meta[:line], true}

      _ ->
        nil
    end)
  end

  defp multi_clause_functions(functions) do
    functions
    |> Enum.frequencies_by(&function_id/1)
    |> Enum.filter(fn {_id, count} -> count > 1 end)
    |> Enum.map(fn {id, _count} -> id end)
    |> MapSet.new()
  end

  defp multi_clause_function?(function, multi_clause_functions) do
    MapSet.member?(multi_clause_functions, function_id(function))
  end

  defp function_id(%{name: name, args: args}), do: {name, length(args)}

  defp redundant_wrapper?(
         %{name: name, head: head, args: args, body: body} = function,
         source_file
       )
       when is_atom(name) do
    not boundary_callback?(name, source_file) and
      not AST.function_has_guard?(head) and
      not AST.meaningful_pattern_args?(args) and
      not AST.function_body_has_rescue?(body) and
      trivial_body?(function)
  end

  defp redundant_wrapper?(_, _), do: false

  defp trivial_body?(%{args: args, do_block: body}) do
    wrapper_args = MapSet.new(Enum.map(args, &AST.variable_name/1) |> Enum.reject(&is_nil/1))

    case AST.block_expressions(body) do
      [call] ->
        not structured_literal?(call) and delegating_call?(call, wrapper_args)

      [{:=, _, [left, right]}, {:ok, returned}] ->
        not is_nil(AST.variable_name(left)) and delegating_call?(right, wrapper_args) and
          AST.same_variable?(returned, AST.variable_name(left))

      [call, {:ok, _ignored}] ->
        delegating_call?(call, wrapper_args)

      _ ->
        false
    end
  end

  defp delegating_call?(call, wrapper_args) do
    remote_or_local_call?(call) and
      call
      |> call_argument_variables()
      |> Enum.all?(&MapSet.member?(wrapper_args, &1))
  end

  defp call_argument_variables(call) do
    case AST.call_identity(call) do
      %{args: args} ->
        Enum.map(args, &AST.variable_name/1)

      _ ->
        []
    end
  end

  defp remote_or_local_call?(node) do
    case AST.call_identity(node) do
      %{function: function} when function in @non_delegating_calls -> false
      %{function: function} when is_atom(function) -> static_remote_or_local_call?(node)
      _ -> false
    end
  end

  defp static_remote_or_local_call?({{:., _, [receiver, _function]}, _, _args}) do
    static_receiver?(receiver)
  end

  defp static_remote_or_local_call?({_function, _meta, args}) when is_list(args), do: true

  defp static_receiver?({:__aliases__, _, _parts}), do: true
  defp static_receiver?(receiver) when is_atom(receiver), do: true
  defp static_receiver?(_receiver), do: false

  defp structured_literal?({:%{}, _meta, _pairs}), do: true
  defp structured_literal?({:%, _meta, [_module, {:%{}, _, _pairs}]}), do: true
  defp structured_literal?({:{}, _meta, _items}), do: true
  defp structured_literal?(list) when is_list(list), do: true
  defp structured_literal?(_node), do: false

  defp boundary_callback?(:render, source_file), do: web_file?(source_file.filename)

  defp boundary_callback?(name, _source_file),
    do:
      name in [:handle_event, :handle_call, :handle_info, :handle_params] or
        String.starts_with?(Atom.to_string(name), "handle_")

  defp web_file?(filename) when is_binary(filename) do
    normalized = String.replace(filename, "\\", "/")

    String.contains?(normalized, "_web/") or String.contains?(normalized, "/web/")
  end

  defp web_file?(_filename), do: false

  defp issue_for(%{name: name, line: line}, issue_meta) do
    format_issue(issue_meta,
      message: @message,
      trigger: Atom.to_string(name),
      line_no: line
    )
  end
end
