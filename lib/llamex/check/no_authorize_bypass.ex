defmodule Llamex.Check.NoAuthorizeBypass do
  @moduledoc """
  Flags `authorize?: false` in Ash action calls and code interface invocations.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [skip_tests: true],
    explanations: [
      check: """
      Ash actions must receive the actor that started the call. System-initiated
      actions (Oban jobs, seeds, migrations) must pass `authorize?: %{system: :name}`
      or a system actor instead of `authorize?: false`.

      This check flags any call that passes `authorize?: false` as a keyword
      option. It walks up from each occurrence to verify the call is an Ash-related
      invocation: a direct `Ash.*` call, an `Ash.Changeset.*` or `Ash.Query.*`
      call, or a domain interface call on a dotted module.

      Remove `authorize?: false` and pass the real actor. For system-initiated
      actions, pass `actor: %{system: :job_name}` or a similar system marker.
      """,
      params: [
        skip_tests:
          "When true, files under `test/`, `*_test.exs` files, and files under `lib/mix/tasks/` are skipped."
      ]
    ]

  alias Credo.IssueMeta
  alias Llamex.Analysis.{Ash, AST, Source}

  @message "Do not use authorize?: false. Pass the actor that started the call, or actor: {system, :name} for system-initiated actions"

  @impl true
  def run(source_file, params \\ []) do
    if Source.skip_tests?(source_file, params, __MODULE__) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> AST.ast()
      |> AST.walk(&authorize_bypass_issue(&1, issue_meta))
    end
  end

  defp authorize_bypass_issue(node, issue_meta) do
    if Ash.authorize_false?(node) do
      call = AST.call_identity(node)

      format_issue(issue_meta,
        message: @message,
        trigger: call && call.trigger,
        line_no: call && call.line
      )
    end
  end
end
