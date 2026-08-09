## Commit Workflow

- **NEVER commit unless the user explicitly asks to commit or confirms the fix is correct.** After making changes, report what changed and stop. Wait for "commit" or confirmation. This applies to subagents too.
- If the user is repeatedly swearing or escalating frustration, stop making opportunistic or random code changes. Re-read the exact request and relevant docs, inspect the existing implementation fully, analyze the actual data and behavior needed, then make the smallest correct systemic fix.
- load hunk-review skill for user to review files, especially if asked. If user asks for review, use hunk only, no gh or PR bullshit.
- During normal development, run the smallest relevant check for the change. Do not run the entire quality suite after every edit unless the user asks for it or the change is broad enough to justify it.
- Prefer integration tests that span at least three units over redundant unit tests that miss real behavior, especially for button clicks, LiveView events, job spawns/cancellation, PubSub updates, and source import flows.
- Before each commit, run these commands in order:
  1. `mix format`
  2. `mix compile --warnings-as-errors`
  3. `mix credo --strict`
  4. `mix deps.unlock --unused`
  5. `mix test`
- If a check fails:
  1. Read the output.
  2. Fix the cause.
  3. Run the failed check again.
- Repeat other checks only if the fix can affect their results.
- If Credo requests an alias, add the alias. Do not change the Credo configuration to suppress the result.
- No "pre-existing issues" excuse — fix everything.
- When told to "commit all", commit ALL changed files — including formatting changes, config files, anything `git status` shows as modified. Never silently skip files.
- On "commit all" — just run `git diff`, run checks, stage and commit. Skip `git status` and `git log` unless specifically needed.
- Commit messages must be detailed multiline messages.
- Do not write tests for CSS changes. Testing "class1" == "class2" proves nothing.

## Subagent Rules

Every subagent prompt MUST include:
1. "Read `/home/dmitriid/Projects/sleever/AGENTS.md` first" — non-negotiable
2. If ANY Ash resource attribute/relationship changes: `mix ash.codegen --name <name>` then `mix ash.migrate`
3. Run full quality checks (see Commit Workflow above). Fix ALL issues.
4. Never wrap a shared function in a pointless one-liner defp. Import it.
5. Merge work and migrate DB before claiming done.

## Ash Rules

- Always use Ash, not Ecto. Always use ash-related mix commands (`mix ash.codegen --name <name>`, `mix ash.migrate`), never ecto equivalents.
- Never generate duplicate migration names. If a feature needs multiple Ash migrations, give each `mix ash.codegen --name` a distinct lower_snake_case name; appending a count or step suffix is fine, e.g. `sleeve_catalog_1`, `sleeve_catalog_2`.
- ALWAYS pass proper actor to all Ash queries UNLESS explicitly allowed by policies. Admin functionality MUST be gated behind an actor. Public functionality doesn't need an actor and must be explicitly allowed in policies.
- Always use code interfaces on domains that reference code interfaces on resources.
- Never do ad-hoc queries anywhere.
- Always use proper `prepare build(...)` and `sort` macros inside Ash resource actions. Avoid lambdas inside them.
- Do not add explicit custom preparation or change modules unless there is no cleaner way to structure the Ash action itself.
- If a custom Ash preparation or change module is created for reuse, document the intended reuse explicitly in that module's `@moduledoc` or adjacent project documentation. If the reuse cannot be stated clearly, do not create the module.
- Do not standalone `Ash.load`, or rely on AshNotLoaded statuses. Load in the relevant action.

## Phoenix 1.8 Rules

- Always begin LiveView templates with `<Layouts.app flash={@flash} ...>` wrapping all inner content
- `MyAppWeb.Layouts` is aliased in `my_app_web.ex`, no need to alias again
- `current_scope` errors: fix by moving routes to proper `live_session` and passing `current_scope` to `<Layouts.app>`
- `<.flash_group>` is forbidden outside `layouts.ex` module
- Always use `<.icon name="hero-x-mark" class="w-5 h-5"/>` for icons, never `Heroicons` modules
- Always use imported `<.input>` component for form inputs from `core_components.ex`
- Overriding `<.input class="...">` removes ALL default classes — custom classes must fully style it

## CSS Rules

- CSS is an exception engine. Define styles as generic as possible, override only in very extreme cases.
- Never use `@apply` in raw CSS. Never use daisyUI. Write custom tailwind-based components.
- Do not reimplement styles from scratch — existing implementations exist for cards, buttons, toggles etc.
- Never duplicate color/background declarations. Use existing classes like `section-text-content--colored`, `panel-accent`, `panel-secondary`, `panel-surface` for colored backgrounds.
- No small buttons or text — never use `btn-sm`, `text-sm`, `text-xs` unless explicitly asked.

## JS/CSS Bundles

Tailwind v4 uses import syntax in `app.css` (no `tailwind.config.js`):
```
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/sleever_web";
```

- Only `app.js` and `app.css` bundles are supported
- Cannot reference external vendor script `src` or link `href` in layouts
- Must import vendor deps into app.js and app.css
- Never write inline `<script>` tags within templates

## UI Rules

- ALL UI TEXT MUST BE GEARED TO HUMANS, NOT MACHINES. Do not expose internal implementation details, job names, source-import mechanics, parsing language, database terms, or agent/LLM planning language in user-facing copy. Write for someone trying to find sleeve sizes for board games.
- Flash messages are for absolute emergencies only. Do not use them for obvious state changes.
- Follow mockup styles exactly when a mockup exists. Do not deviate or use default tailwind styles.
- Avoid large modules. Split LiveViews — extract components, event handlers, helpers to separate modules.

## Documentation

All plans, issues, design docs use format: `<YYMMDD-HHmm-name.md>` in:
- `docs/plans` — current plans
- `docs/issues` — discovered issues
- `docs/designs` — frontend design docs, prototypes
- `docs/sleever` — system/app documentation, architectural decisions

## Dependencies

- Always use `mix igniter.install` to add Elixir dependencies (never edit mix.exs manually for deps)
- Use `Req` for HTTP requests, never httpoison/tesla/httpc

## Reference Projects

- `../muqui` — imgproxy proxy logic and config, LiveView splitting approach
- `../quire` — Markdown AST processing, media URL parsing
only output ASD-STE100 Simplified Technical English in comments, docs, and communication with user
