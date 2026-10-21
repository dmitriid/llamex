defmodule Llamex do
  @moduledoc """
  Credo checks for issues commonly introduced by LLM-assisted Elixir refactors.
  """

  import Credo.Plugin

  @checks [
    Llamex.Check.NoOneLiners,
    Llamex.Check.NoAdHocAshQueries,
    Llamex.Check.ConsistentInterfaces,
    Llamex.Check.NoDBWorkInMemory,
    Llamex.Check.NoAuthorizeBypass,
    Llamex.Check.NoSelfInLiveViews,
    Llamex.Check.NoMultipleAssigns,
    Llamex.Check.NoAshReadForExistenceCheck
  ]

  @optional_checks [
    llmisms_in_comments: Llamex.Check.NoLLMismsInComments,
    llmisms_in_markdown: Llamex.Check.NoLLMismsInMarkdown
  ]

  # The Credo commands that print issues with their source lines.
  @analysis_commands ["suggest", "list", "diff"]

  @doc "Returns all checks that the plugin enables by default."
  def checks, do: @checks

  @doc """
  Returns the checks that the plugin enables only on request.

  Each key is a plugin option. Set the option to `true` to enable the
  check with default params. Set it to a keyword list to enable the
  check with those params.
  """
  def optional_checks, do: @optional_checks

  @doc false
  def init(exec) do
    exec = prepend_task(exec, :validate_config, Llamex.Credo.AddChecks)

    Enum.reduce(@analysis_commands, exec, fn command, exec ->
      append_task(exec, command, :run_analysis, Llamex.Credo.AddMarkdownFiles)
    end)
  end
end
