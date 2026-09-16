defmodule Llamex.Analysis.AST do
  @moduledoc """
  General-purpose AST traversal and inspection helpers.

  These functions extract structure from Elixir AST nodes: function
  definitions, aliases, module attributes, call identities, pipe
  inputs, and variable assignments.
  """

  alias Credo.SourceFile

  @collection_modules [Enum, List, Stream]

  def ast(%SourceFile{} = source_file), do: SourceFile.ast(source_file)

  def walk(ast, fun) when is_function(fun, 1) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn node, acc ->
        case fun.(node) do
          nil -> {node, acc}
          value -> {node, [value | acc]}
        end
      end)

    Enum.reverse(acc)
  end

  def walk_with_ancestors(ast, fun) when is_function(fun, 2) do
    {_ast, {_ancestors, acc}} =
      Macro.traverse(
        ast,
        {[], []},
        fn node, {ancestors, acc} ->
          acc =
            case fun.(node, ancestors) do
              nil -> acc
              value -> [value | acc]
            end

          {node, {[node | ancestors], acc}}
        end,
        fn node, {[_current | ancestors], acc} ->
          {node, {ancestors, acc}}
        end
      )

    Enum.reverse(acc)
  end

  def module_uses(ast) do
    ast
    |> module_use_calls()
    |> Enum.map(& &1.module_name)
  end

  def module_use_calls(ast) do
    walk(ast, fn
      {:use, meta, [module | args]} ->
        %{
          module: alias_to_atom(module),
          module_name: alias_to_string(module),
          args: args,
          line: meta[:line]
        }

      _ ->
        nil
    end)
  end

  def aliases(ast) do
    walk_with_ancestors(ast, fn
      {:alias, _meta, [{:__aliases__, _, parts}]}, ancestors ->
        alias_entry(parts, nil, ancestors)

      {:alias, _meta, [{:__aliases__, _, parts}, opts]}, ancestors when is_list(opts) ->
        alias_entry(parts, Keyword.get(opts, :as), ancestors)

      _, _ ->
        nil
    end)
    |> Map.new()
  end

  defp alias_entry(parts, as, ancestors) do
    with {:ok, resolved_parts} <- resolve_module_parts(parts, ancestors),
         {:ok, as_name} <- resolve_as(as, resolved_parts) do
      {as_name, Module.concat(resolved_parts)}
    else
      :error -> nil
    end
  end

  defp resolve_module_parts([{:__MODULE__, _, _} | rest], ancestors) do
    case enclosing_module_parts(ancestors) do
      [] -> :error
      module_parts -> {:ok, module_parts ++ rest}
    end
  end

  defp resolve_module_parts(parts, _ancestors) do
    if Enum.all?(parts, &is_atom/1), do: {:ok, parts}, else: :error
  end

  defp resolve_as(nil, resolved_parts), do: {:ok, List.last(resolved_parts)}
  defp resolve_as(as, _resolved_parts) when is_atom(as), do: {:ok, as}

  defp resolve_as({:__aliases__, _, as_parts}, _resolved_parts) do
    case List.last(as_parts) do
      name when is_atom(name) -> {:ok, name}
      _ -> :error
    end
  end

  defp resolve_as(_as, _resolved_parts), do: :error

  defp enclosing_module_parts(ancestors) do
    ancestors
    |> Enum.filter(&match?({:defmodule, _, [{:__aliases__, _, _}, _]}, &1))
    |> Enum.reverse()
    |> Enum.flat_map(fn {:defmodule, _, [{:__aliases__, _, parts}, _]} -> parts end)
  end

  def opt_out?(ast, attribute) do
    Enum.any?(walk(ast, &module_attribute(&1, attribute)), &(&1 == true))
  end

  def functions(ast) do
    walk(ast, fn
      {:def, meta, [head, body]} -> function_tuple(:def, meta, head, body)
      {:defp, meta, [head, body]} -> function_tuple(:defp, meta, head, body)
      _ -> nil
    end)
  end

  def function_name({:when, _, [head | _]}), do: function_name(head)

  def function_name({name, _, args}) when is_atom(name) and (is_list(args) or is_nil(args)),
    do: name

  def function_name(_), do: nil

  def function_args({:when, _, [head | _]}), do: function_args(head)
  def function_args({_name, _, args}) when is_list(args), do: args
  def function_args({_name, _, nil}), do: []
  def function_args(_), do: []

  def function_has_guard?({:when, _, _}), do: true
  def function_has_guard?(_), do: false

  def function_body(keyword) when is_list(keyword), do: Keyword.get(keyword, :do)

  def function_body_has_rescue?(keyword) when is_list(keyword) do
    Enum.any?([:rescue, :catch, :after], &Keyword.has_key?(keyword, &1))
  end

  def meaningful_pattern_args?(args) do
    Enum.any?(args, fn
      {name, _, context} when is_atom(name) and is_atom(context) -> false
      _ -> true
    end)
  end

  def block_expressions({:__block__, _, expressions}), do: expressions
  def block_expressions(nil), do: []
  def block_expressions(expression), do: [expression]

  def assignment?({:=, _, [left, right]}), do: {true, left, right}
  def assignment?(_), do: false

  def variable_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  def variable_name(_), do: nil

  def same_variable?({name, _, context}, expected) when is_atom(name) and is_atom(context) do
    name == expected
  end

  def same_variable?(_, _), do: false

  def call_identity({{:., _, [module_ast, function]}, meta, args})
      when is_atom(function) and is_list(args) do
    %{
      module: alias_to_atom(module_ast),
      module_name: alias_to_string(module_ast),
      function: function,
      arity: length(args),
      args: args,
      line: meta[:line],
      trigger: "#{alias_to_string(module_ast)}.#{function}"
    }
  end

  def call_identity({function, meta, args}) when is_atom(function) and is_list(args) do
    %{
      module: nil,
      module_name: nil,
      function: function,
      arity: length(args),
      args: args,
      line: meta[:line],
      trigger: Atom.to_string(function)
    }
  end

  def call_identity(_), do: nil

  def pipe_input({:|>, _, [input, _right]}), do: input
  def pipe_input(_), do: nil

  def innermost_pipe_input({:|>, _, [input, _right]}), do: innermost_pipe_input(input)
  def innermost_pipe_input(expression), do: expression

  def collection_call?(node) do
    case call_identity(node) do
      %{module: module, function: function} when module in @collection_modules ->
        function in [
          :all?,
          :any?,
          :chunk_every,
          :count,
          :filter,
          :find,
          :flat_map,
          :group_by,
          :map,
          :reject,
          :sort,
          :sort_by,
          :take,
          :uniq,
          :uniq_by
        ]

      _ ->
        false
    end
  end

  def ash_module_name?(nil), do: false

  def ash_module_name?(module_name),
    do: module_name == "Ash" or String.starts_with?(module_name, "Ash.")

  def alias_to_atom({:__aliases__, _, parts}), do: Module.concat(parts)
  def alias_to_atom(atom) when is_atom(atom), do: atom
  def alias_to_atom(_), do: nil

  def alias_to_string({:__aliases__, _, parts}), do: Enum.join(parts, ".")
  def alias_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  def alias_to_string(other), do: Macro.to_string(other)

  def call_to_string({{:., _, [module_ast, function]}, _, _}) do
    "#{alias_to_string(module_ast)}.#{function}"
  end

  def call_to_string({function, _, _}) when is_atom(function), do: Atom.to_string(function)
  def call_to_string(expression), do: Macro.to_string(expression)

  def resolve_alias(module, aliases) when is_atom(module) do
    if elixir_module?(module) do
      resolve_elixir_alias(module, aliases)
    else
      module
    end
  end

  def resolve_alias(module, _aliases), do: module

  # Module.split/1 raises for Erlang module atoms such as :crypto.
  defp elixir_module?(module), do: String.starts_with?(Atom.to_string(module), "Elixir.")

  defp resolve_elixir_alias(module, aliases) do
    case Module.split(module) do
      [single] ->
        Map.get(aliases, String.to_atom(single), module)

      [first | rest] ->
        case Map.get(aliases, String.to_atom(first)) do
          nil -> module
          resolved -> Module.concat([resolved | rest])
        end
    end
  end

  defp function_tuple(kind, meta, head, body) do
    %{
      kind: kind,
      meta: meta,
      name: function_name(head),
      args: function_args(head),
      head: head,
      body: body,
      do_block: function_body(body),
      line: meta[:line]
    }
  end

  defp module_attribute({:@, _, [{attribute, _, [value]}]}, attribute), do: value
  defp module_attribute(_, _), do: nil
end
