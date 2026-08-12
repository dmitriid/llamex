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
    Llamex.Check.NoSelfInLiveViews
  ]

  @doc "Returns all checks shipped by Llamex."
  def checks, do: @checks

  @doc false
  def init(exec) do
    prepend_task(exec, :validate_config, Llamex.Credo.AddChecks)
  end
end
