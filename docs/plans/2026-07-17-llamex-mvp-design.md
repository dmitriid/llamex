# Llamex MVP Design

## Goal

Llamex is a Credo plugin suite that catches issues commonly introduced by LLM-assisted Elixir refactorings. The MVP ships all four planned checks:

- `Llamex.Check.NoOneLiners`
- `Llamex.Check.NoAdHocAshQueries`
- `Llamex.Check.ConsistentInterfaces`
- `Llamex.Check.NoDBWorkInMemory`

The first release prioritizes detection, useful messages, and conservative behavior around uncertainty. It does not include automatic fixes.

## Project Status

This project is vibe-coded. An AI coding agent wrote most of the code with little user input. We tested the checks on real Elixir projects, but this does not guarantee correct results in every project. Users must review each finding before they change code. Results can vary (YMMV).

Source brief: [project-description.md](../../project-description.md).

## User-Facing Configuration

Llamex uses standard Credo configuration. Users enable, disable, and tune each check through normal Credo params in `.credo.exs`.

The MVP should not introduce a shared Llamex config block. Configuration should stay per-check until the rules have been used enough to justify shared options.

Suppressions should work through Credo's existing inline disable mechanisms. Llamex also supports targeted opt-out attributes where the behavior is sometimes intentional, especially for `NoDBWorkInMemory`.

## Architecture

The package is structured as Credo checks plus shared analysis modules:

- `Llamex.Check.*` modules handle Credo integration, params, AST traversal entry points, issue construction, messages, and priorities.
- `Llamex.Analysis.*` modules handle reusable AST analysis such as calls, pipes, assignments, variable origins, aliases, module attributes, and function identity.
- Ash-aware analysis resolves domains, resources, interfaces, actions, and modules that `use Ash.*` only from a suspected issue location or from modules reached while tracing that issue.

Checks should not each implement their own tracing, alias resolution, module lookup, AST navigation, confidence handling, or opt-out detection. They should call common helpers and provide only rule-specific predicates, allowed exceptions, and issue messages. If two checks need the same kind of context, that context belongs in `Llamex.Analysis.*`, not in either check module.

None of the MVP checks should require full-project scanning. Each check starts from a local problematic pattern found in the current file, then traces outward only as far as needed to classify that specific finding. Shared helpers may memoize files and modules already inspected during the Credo run, but they should not require a complete project index.

The checks share a confidence model:

- `:proven` means the source of the issue is known from local AST or reliable metadata resolved from the suspect location.
- `:likely` means the issue is strongly indicated, but part of the path depends on simple inference.
- `:possible` means the analyzer found a plausible path, but incomplete information prevents a stronger conclusion.

Proven and likely findings use the configured check severity, with likely findings using more careful wording. Possible findings default to `info` where uncertainty is expected, especially in `NoDBWorkInMemory`.

Project context should be resolved on demand. A check may use cheap compiler metadata, Mix path conventions, or already-loaded module information to jump from a suspect call to a specific module or file. It should not parse unrelated files just to prepare for possible findings.

Shared analysis helpers should include:

- A source context helper for current module, function, aliases, imports, attributes, and local definitions.
- A call identity helper for normalizing local, remote, imported, and piped calls.
- A variable-origin tracer for assignments, pipes, parameters, helper calls, and simple return values.
- A demand-driven module resolver that maps a reached module to a source file and memoizes parsed AST.
- An Ash classifier for `use Ash.*` modules, domains, resources, interfaces, and actions reached during tracing.
- A confidence helper that records why a finding is `:proven`, `:likely`, or `:possible`.
- An opt-out helper that understands Credo disables and Llamex attributes.

Check modules should be thin. For example, `NoDBWorkInMemory` should ask the shared tracer where a collection came from; `NoAdHocAshQueries` should ask the shared call identity and Ash classifier what kind of call it found; `ConsistentInterfaces` should ask the shared Ash resolver about the referenced action. None of those checks should duplicate traversal infrastructure.

## Check Behavior

### NoOneLiners

`Llamex.Check.NoOneLiners` flags redundant wrapper functions where the body only delegates to another function or performs a trivial assign-and-return shape.

It should detect:

- One-line `def` wrappers.
- Multi-line `do:` wrappers.
- Block bodies that only delegate.
- Trivial assignment followed by direct return of the assigned value.
- Trivial helper call followed by a synthetic success tuple when the helper result is ignored.

Examples that should be flagged:

```elixir
def search_for_record(id), do: Search.search_for_record(id)

def get_record(id) do
  value = Search.get_one_record!(id)
  {:ok, value}
end

def mark_invalid(id) do
  Search.mark_record_as_invalid!(id)
  {:ok, :done}
end
```

It should not flag wrappers that materially change behavior, including:

- `rescue`, `catch`, or `after`.
- Guards or pattern matching that narrow accepted inputs in a meaningful way.
- Instrumentation, logging, authorization, or validation.
- Boundary callbacks where delegation is usually intentional, such as Phoenix and LiveView-style `handle_event`, `handle_call`, `handle_info`, `handle_params`, and other `handle_*` functions.

Examples that should not be flagged:

```elixir
def search_for_record(id) do
  Search.search_for_record!(id)
rescue
  error -> {:error, error}
end

def handle_event("search:" <> event, params, socket) do
  Search.handle_input(event, params, socket)
end
```

Default severity: `error`.

Default message: `Redundant one-line wrapper. Replace with direct call`.

### NoAdHocAshQueries

`Llamex.Check.NoAdHocAshQueries` flags ad-hoc Ash query and changeset construction where project conventions require domain interfaces.

It should detect:

- Direct calls to `Ash.*` query and changeset APIs from ordinary application modules.
- Calls such as `Ash.Query.*`, `Ash.Changeset.*`, `Ash.read!`, `Ash.create!`, `Ash.update!`, and similar direct execution APIs where they bypass domain interfaces.
- Domain interface calls that pass ad-hoc query options inline, such as `load`, `offset`, `limit`, or filtering options.

The entry point is the suspect call itself: an `Ash.*` call or a call expression with inline query options. The check should resolve the current module and the called module only as needed to decide whether the location is an allowed Ash implementation module or a domain interface call.

Examples that should be flagged:

```elixir
def create_ticket(params) do
  Helpdesk.Support.Ticket
  |> Ash.Changeset.for_create(:open, params)
  |> Ash.create!()
end

def get_records_for_user(id) do
  Helpdesk.Support.get_user_records!(
    id,
    load: [:comments, :statuses, :related],
    offset: 20
  )
end
```

It should allow:

- Aggregate terminal calls such as `Ash.count!`, `Ash.sum!`, `Ash.avg!`, `Ash.min!`, and `Ash.max!` when used on a read query.
- Ash usage inside implementation modules that `use Ash.Resource.*`, changes, calculations, preparations, validations, aggregates, policies, and similar extension points.

Examples that should be allowed:

```elixir
def no_of_records do
  Helpdesk.Support.list_all_tickets()
  |> Ash.count!()
end

defmodule Sleever.Sleeves.Changes.SetSourceSubmitter do
  use Ash.Resource.Change

  def change(changeset, _opts, %{actor: %{id: actor_id}}) do
    Ash.Changeset.force_change_attribute(changeset, :submitter_id, actor_id)
  end
end
```

Domain modules need separate scrutiny because they define public interfaces. They should not be treated as a blanket exception.

Default severity: `warning`.

Default message: `Avoid ad-hoc queries. Use domain interfaces instead`.

### ConsistentInterfaces

`Llamex.Check.ConsistentInterfaces` compares Ash domain interface declarations against referenced resource action names and argument shapes.

It should detect:

- Domain `define` declarations where the interface name differs from the referenced action name.
- Redundant argument remapping when an interface name already matches the action and the action accepts the same arguments.
- Interface declarations whose argument shape appears inconsistent with the resource action.

The entry point is the `define` declaration in the current domain/resource DSL block. The check should resolve only the referenced resource and action needed for that declaration. It should not scan every domain or resource to build a complete interface map.

Examples that should be flagged:

```elixir
resource Sleever.Sleeves.CardSize do
  define :suggest_card_size_matches,
    action: :list_and_suggest_matched_cards,
    args: [:input]

  define :create_or_link_card_size_source,
    args: [:input]
end
```

Findings should name the domain, resource, interface, action, and suspected mismatch where available.

The MVP should not rewrite interface declarations. It should provide actionable messages and leave final naming decisions to the developer.

Default severity: `warning`.

Default message: `Keep interface names consistent with action names. Avoid redundant arg passing`.

### NoDBWorkInMemory

`Llamex.Check.NoDBWorkInMemory` detects in-memory collection work on data that originates from database-backed Ash queries or domain interfaces.

It should detect `Enum.*`, `List.*`, and similar collection operations when the collection originates from:

- An Ash domain interface.
- An Ash resource read.
- A function whose return value traces back to an Ash domain interface or resource read.

Proven cases remain `error`. For example, `Tickets.list_all_tickets!() |> Enum.filter(...)` is a proven finding.

Examples that should be flagged:

```elixir
def show_invalid_records do
  books = Books.get_all_books!()

  books
  |> Enum.reject(&is_nil/1)
  |> Enum.filter(&(&1.status == :invalid))
end

def invalid_records_for(user) do
  user
  |> records_for_user()
  |> Enum.filter(&(&1.status == :invalid))
end

defp records_for_user(user) do
  Books.records_for_user!(user)
end
```

Likely cases use the configured severity with cautious wording. For example, a simple helper in another module that returns a traced query result may be likely rather than proven if some alias or dispatch detail is inferred.

Possible cases emit `info`, using wording such as `Possible DB work in memory`. These cases should appear when tracing finds a plausible origin but cannot prove it.

The check needs an opt-out mechanism for justified cases:

```elixir
@llamex_db_work_in_memory_allowed true
```

The attribute should work at module scope and near a specific function. Credo inline disables should also work.

Findings should include the traced path when available, because the rule is only useful if the developer can see how Llamex concluded the collection came from the database.

Default severity: `error` for proven cases.

Default message: `Do not operate on the whole dataset in memory. Use DB queries via resources`.

## Demand-Driven Tracing

`NoDBWorkInMemory` starts from the function where in-memory work is detected. It must not scan the entire project to find every possible source for every finding.

The analyzer should not require scanning and parsing the entire project up front. It should build lookup data lazily from the current file and from specific files it has a reason to inspect.

Lookup data can include:

- Module definitions in files already inspected.
- Function heads for modules reached during tracing.
- Aliases and imports in files already inspected.
- Module attributes in the current module or a reached module.
- `use Ash.*` markers in the current module or a reached module.
- Ash domain and resource declarations only when a reached module needs Ash classification.
- Function call references only for the current function, reached helper functions, or known direct callers when tracing from a parameter.

These lookups are support data, not the tracing result. They should be memoized during the Credo run so repeated checks do not reparse the same file.

A cheap discovery layer may map module names to source files using compiler metadata, project conventions, or Mix paths. That mapping is acceptable because it avoids parsing file contents. Full AST parsing should remain demand-driven.

For each detected in-memory operation, the tracer follows the collection expression backwards inside the current function first:

- Pipe input.
- Assigned variable.
- Struct or list access.
- Local helper call.
- Function parameter.

Only when the local origin points outward should the tracer resolve and inspect a specific callee or caller. If the collection comes from a parameter, the tracer can consult known direct callers if that information is available cheaply; otherwise it should degrade to `:possible` or stop. If the collection comes from a helper, it should inspect that helper's return path directly.

The tracer should set hard limits for depth, file count, and recursion cycles so Credo stays responsive. It should prefer exact module/function/arity matches, degrade confidence when dispatch is dynamic or aliases are unclear, and stop at external dependencies unless they are known Ash modules.

## Error Handling

Llamex should fail soft.

If Ash or Spark metadata cannot be loaded, checks that need it should degrade to AST-only detection and avoid crashing the Credo run. If aliases, macros, generated code, or dynamic dispatch are unclear, the check should degrade confidence or skip the finding depending on the rule.

Unexpected parser or metadata errors should be captured as debug diagnostics rather than user-facing Credo issues, unless the user explicitly enables a diagnostic mode.

## Testing

Testing should lean on integration-style Credo runs against fixture projects rather than only unit-testing AST helpers.

Each check needs fixture files for positive, negative, and edge cases. Shared analysis modules need unit tests for:

- AST traversal.
- Alias resolution.
- Pipe handling.
- Assignment and variable origin tracking.
- Function identity.
- Demand-driven module resolution.
- Ash classification from reached modules.
- Opt-out detection.
- Confidence degradation.

Tests should make duplicated analysis behavior visible. When adding a second check that needs existing traversal or tracing behavior, coverage should exercise the shared helper rather than re-testing a private reimplementation inside the check.

`NoDBWorkInMemory` needs multi-file fixtures that prove demand-driven tracing:

- Local assignment.
- Helper return.
- Parameter-to-caller lookup.
- Cross-module direct calls.
- Cycles.
- Unknown dynamic calls.
- `info` findings for uncertain origins.

Performance tests or bounded integration fixtures should assert that tracing does not inspect unrelated modules once it has a starting function and memoized lookup cache.

Fail-soft behavior should be tested when Ash is absent or Spark metadata cannot be read.

## Delivery

The MVP is a standard Hex-ready Credo plugin package.

`mix.exs` should add Credo and Ash/Spark dependencies carefully. Ash/Spark should be optional where possible if checks can degrade without them.

Documentation should show:

- `.credo.exs` configuration for each check.
- Severity defaults.
- Opt-out attributes.
- Example findings.
- The confidence model.
- Known limitations of demand-driven tracing.

This repository path is not currently a git repository, so this design document cannot be committed until a repository is initialized or the work is moved into an existing git checkout.
