# Llamex

Llamex is a Credo plugin suite. It detects issues that LLM-assisted Elixir
refactors commonly introduce. The suite ships seven checks:

- `Llamex.Check.NoOneLiners`
- `Llamex.Check.NoAdHocAshQueries`
- `Llamex.Check.ConsistentInterfaces`
- `Llamex.Check.NoDBWorkInMemory`
- `Llamex.Check.NoAuthorizeBypass`
- `Llamex.Check.NoSelfInLiveViews`
- `Llamex.Check.NoMultipleAssigns`

The checks detect problems and show useful messages. They do not apply
automatic fixes.

## Project Status

This project is vibe-coded. An AI coding agent wrote most of the code with
little user input. We tested the checks on real Elixir projects, but this does
not guarantee correct results in every project. Review each finding before you
change code. Your results can vary (YMMV).

For a detailed description of the checks and their initial goals, see the
[project description](project-description.md).

## Installation

Llamex is not a published Hex package. Clone the repository next to your
Elixir project:

```sh
git clone https://github.com/dmitriid/llamex.git
```

Then, add Llamex to your project as a local dependency. This example expects
the Llamex and project directories to have the same parent directory:

```elixir
def deps do
  [
    {:llamex, path: "../llamex", only: [:dev, :test], runtime: false}
  ]
end
```

Run `mix deps.get` in your project after you add the dependency.

To enable the full suite as a Credo plugin, add `Llamex` to `.credo.exs`:

```elixir
%{
  configs: [
    %{
      name: "default",
      plugins: [
        {Llamex, []}
      ]
    }
  ]
}
```

The plugin injects all shipped checks after the project config loads. It
works with projects that use `checks.enabled`. The plugin skips test files
and Mix task files by default. To lint those files too:

```elixir
plugins: [
  {Llamex, [skip_tests: false]}
]
```

To enable only selected checks, configure those modules directly:

```elixir
%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
          {Llamex.Check.NoOneLiners, []},
          {Llamex.Check.NoDBWorkInMemory, [skip_tests: false]}
        ]
      }
    }
  ]
}
```

Every check supports `skip_tests`, which defaults to `true`. When enabled, it
skips files under `test/`, `*_test.exs` files, and files under `lib/mix/tasks/`.

## Checks

### NoOneLiners

Default severity: error-level priority.

This check flags redundant wrapper functions. It detects three patterns:

1. The body only delegates to another function.
2. The body assigns a delegated value and returns it.
3. The body ignores a helper result and returns a synthetic success tuple.

Flagged examples:

```elixir
def search_for_record(id), do: Search.search_for_record(id)

def get_record(id) do
  value = Search.get_one_record!(id)
  {:ok, value}
end
```

The check skips these cases:

- Guarded or pattern-narrowing heads
- Rescue/catch/after bodies
- Boundary callbacks: `handle_event/3`, `handle_call/3`, `handle_info/2`,
  `handle_params/3`, web-layer `render/*`, and other `handle_*` functions
- `@impl` functions

For intentional thin boundaries that are not callbacks, add this attribute
before the function:

```elixir
@llamex_one_liner_allowed true
```

Default message:

```text
Redundant one-line wrapper. Replace with direct call
```

### NoAdHocAshQueries

Default severity: warning.

This check flags direct `Ash`, `Ash.Query`, and `Ash.Changeset` API calls
in application modules. It also flags domain interface calls that pass
inline query options: `load`, `filter`, `sort`, or `query`.

Pagination options (`page`, `limit`, `offset`) are allowed. Paging at call
time is the Ash-designed API.

Flagged examples:

```elixir
Ticket
|> Ash.Changeset.for_create(:open, params)
|> Ash.create!()

Support.get_user_records!(id, load: [:comments])
```

The check allows aggregate calls like `Ash.count!/1`. It also allows Ash
implementation modules that `use Ash.Resource.*` or similar extension points.

Default message:

```text
Avoid ad-hoc queries. Use domain interfaces instead
```

### ConsistentInterfaces

Default severity: warning.

This check flags Ash domain `define` declarations where the interface name
differs from the referenced action name.

Flagged example:

```elixir
define :suggest_card_size_matches,
  action: :list_and_suggest_matched_cards,
  args: [:input]
```

Default message:

```text
Keep interface names consistent with action names. Avoid redundant arg passing
```

### NoDBWorkInMemory

Default severity: error-level priority for proven local origins.

This check flags `Enum`, `List`, and `Stream` collection work when the
collection traces back to an Ash domain interface or direct Ash read. The
trace stays within the current file. Findings include the traced origin path.

Flagged example:

```elixir
Books.get_all_books!()
|> Enum.reject(&is_nil/1)
|> Enum.filter(&(&1.status == :invalid))
```

To opt out when whole-dataset in-memory work is intentional, add this
module attribute:

```elixir
@llamex_db_work_in_memory_allowed true
```

Credo inline disable comments also suppress findings.

Default message:

```text
Do not operate on the whole dataset in memory. Use DB queries via resources
```

### NoAuthorizeBypass

Default severity: warning.

This check flags `authorize?: false` in Ash action calls, domain interface
calls, and `Ash.Query`/`Ash.Changeset` calls.

Flagged examples:

```elixir
Ash.create!(changeset, authorize?: false)
Support.get_ticket!(id, authorize?: false)
```

Actions must receive the actor that started the call. System-initiated
actions (Oban jobs, seeds, migrations) must pass a system actor instead:

```elixir
# Do not do this:
Support.create_ticket!(params, authorize?: false)

# Do this instead:
Support.create_ticket!(params, actor: user)

# For system-initiated actions:
Support.create_ticket!(params, actor: %{system: :my_oban_job})
```

Default message:

```text
Do not use authorize?: false. Pass the actor that started the call, or
actor: %{system: name} for system-initiated actions
```

### NoSelfInLiveViews

Default severity: warning.

This check reports local `self()` calls inside Phoenix LiveView modules. It
detects modules that use `Phoenix.LiveView` and modules that use the common
project macro form, such as `use MyAppWeb, :live_view`.

The check starts at each `self()` call and checks its parent module.

Flagged example:

```elixir
def mount(_params, _session, socket) do
  send(self(), :load)
  {:ok, socket}
end
```

Default message:

```text
Do not use self() in Phoenix LiveViews. Use start_async/3 or assign_async/3,
and handle the result with built-in Phoenix functions. Use Task or supervisor
trees only in rare cases.
```

### NoMultipleAssigns

Default severity: readability warning. This check does not change the exit
status of `mix credo`. The build does not fail on its findings.

This check reports pipe chains with more than three single-key `assign`
calls. One `assign` call with a keyword list shows all keys in one place.

Flagged example:

```elixir
socket
|> assign(:tab, parse_tab(params["tab"]))
|> assign(:status, parse_status(params["status"]))
|> assign(:page, parse_page(params["page"]))
|> assign(:url_status, parse_status(params["url_status"]))
```

Preferred form:

```elixir
assign(socket,
  tab: parse_tab(params["tab"]),
  status: parse_status(params["status"]),
  page: parse_page(params["page"]),
  url_status: parse_status(params["url_status"])
)
```

The `max_assigns` param sets the threshold. The default value is 3.

Default message:

```text
For readability, avoid multiple assign statements. Use socket |> assign(key1: ..., key2: ...)
```

## Confidence Model

Llamex classifies findings conservatively:

- `:proven` — the source is known from local AST or reliable metadata.
- `:likely` — the issue is strongly indicated through simple inference.
- `:possible` — there is a plausible path but incomplete information.

The current version implements proven local detection and conservative
AST-only heuristics. It fails soft when Ash/Spark metadata is unavailable.

## Known Limitations

- Cross-file tracing is intentionally shallow.
- Dynamic dispatch, generated code, and complex macro expansion may be skipped.
- Ash classification is AST-first. It does not require a full project index.
- Checks do not rewrite code.
