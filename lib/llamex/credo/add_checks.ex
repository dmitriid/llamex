defmodule Llamex.Credo.AddChecks do
  @moduledoc false

  use Credo.Execution.Task

  @impl true
  def call(%Execution{checks: nil} = exec, _opts) do
    %{exec | checks: %{enabled: default_checks(exec), disabled: []}}
  end

  def call(%Execution{checks: %{enabled: enabled} = checks} = exec, _opts)
      when is_list(enabled) do
    checks = %{
      checks
      | enabled:
          exec |> default_checks() |> Keyword.merge(enabled) |> keep_disabled_checks(checks)
    }

    %{exec | checks: checks}
  end

  defp default_checks(exec) do
    opts = exec.plugins[Llamex] || []
    skip_tests = Keyword.get(opts, :skip_tests, true)

    Enum.map(Llamex.checks(), &{&1, [skip_tests: skip_tests]}) ++
      optional_checks(opts, skip_tests)
  end

  defp optional_checks(opts, skip_tests) do
    Enum.flat_map(Llamex.optional_checks(), fn {key, check} ->
      case Keyword.get(opts, key) do
        true -> [{check, [skip_tests: skip_tests]}]
        params when is_list(params) -> [{check, Keyword.put_new(params, :skip_tests, skip_tests)}]
        _disabled -> []
      end
    end)
  end

  defp keep_disabled_checks(enabled, checks) do
    disabled = Keyword.keys(checks[:disabled] || [])

    Enum.reject(enabled, fn {check, params} ->
      check in disabled and params != false
    end)
  end
end
