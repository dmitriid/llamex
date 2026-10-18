# Llamex

Llamex is a Credo plugin suite. It detects issues that LLM-assisted Elixir
refactors commonly introduce. The suite ships nine checks. The plugin
enables seven of them by default:

- `Llamex.Check.NoOneLiners`
- `Llamex.Check.NoAdHocAshQueries`
- `Llamex.Check.ConsistentInterfaces`
- `Llamex.Check.NoDBWorkInMemory`
- `Llamex.Check.NoAuthorizeBypass`
- `Llamex.Check.NoSelfInLiveViews`
- `Llamex.Check.NoMultipleAssigns`

Two checks are optional. The plugin enables them only with plugin options:

- `Llamex.Check.NoLLMismsInComments`
- `Llamex.Check.NoLLMismsInMarkdown`

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

To enable the optional `NoLLMismsInComments` check, set the
`llmisms_in_comments` plugin option. Set it to `true` for the default
params, or to a keyword list with check params:

```elixir
plugins: [
  {Llamex, [llmisms_in_comments: true]}
]

plugins: [
  {Llamex, [llmisms_in_comments: [max_llmisms: 1, window_lines: 5]]}
]
```

To enable the optional `NoLLMismsInMarkdown` check, set the
`llmisms_in_markdown` plugin option. The values are the same as for
`llmisms_in_comments`. This check needs the `:mdex` package. Llamex
declares `:mdex` as an optional dependency, so add it to your project:

```elixir
def deps do
  [
    {:mdex, "~> 0.14", only: [:dev, :test], runtime: false}
  ]
end
```

```elixir
plugins: [
  {Llamex, [llmisms_in_comments: true, llmisms_in_markdown: true]}
]

plugins: [
  {Llamex, [llmisms_in_markdown: [paths: ["*.md", "docs/**/*.md"]]]}
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

Every check except `NoLLMismsInMarkdown` supports `skip_tests`, which
defaults to `true`. When enabled, it skips files under `test/`, `*_test.exs`
files, and files under `lib/mix/tasks/`.

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

### NoLLMismsInComments

Default severity: readability warning. This check does not change the exit
status of `mix credo`. The build does not fail on its findings.

The plugin does not enable this check by default. See the installation
section for the `llmisms_in_comments` plugin option. You can also add the
check module to `checks.extra` directly.

This check scans each `#` comment block and each doc string for phrases
that language models write and people do not. A comment block is a run
of comments on consecutive lines. A doc string is the value of
`@moduledoc`, `@doc`, `@typedoc`, or `@shortdoc`. Each doc string is one
block. The check reports a block when the count of matches is above the
limit for the block size.

The limit is a ratio: `max_llmisms` matches per `window_lines` lines. The
default is 2 per 10. The ratio applies to blocks of every size:

- A block of 10 lines can contain 2 matches. The third match is reported.
- A block of 5 lines can contain 1 match.
- A block of 1 line can contain 0 matches. One match is reported.
- In a block longer than `window_lines`, the check scans every window of
  `window_lines` consecutive lines.

Params:

| Param          | Default | Meaning                                              |
| -------------- | ------- | ---------------------------------------------------- |
| `max_llmisms`  | 2       | The number of matches that `window_lines` lines can contain. |
| `window_lines` | 10      | The number of lines that `max_llmisms` applies to.   |
| `skip_tests`   | true    | Skip test files and Mix task files.                  |

To change the params without the plugin option, configure the check module
directly:

```elixir
checks: %{
  extra: [
    {Llamex.Check.NoLLMismsInComments, [max_llmisms: 1, window_lines: 5]}
  ]
}
```

The check scans for these pattern classes:

- em dashes and semicolons
- contractions, for example `don't` and `it's`
- the modals `should`, `would`, `could`, `might`, and `may`
- present perfect forms, for example `has been` and `have changed`
- words with no fact, for example `simply`, `robust`, `seamless`,
  `leverage`, `elegant`
- Latin abbreviations `e.g.` and `i.e.`, and the phrases `in order to`,
  `prior to`, `in the event that`
- filler phrases, for example `under the hood`, `worth noting`,
  `keep in mind`, `deep dive`
- metaphor verbs, for example `rescues`, `nudges`, `swallows`, `wires up`
- the container verb `hold` and the status verb `stand`
- fact-free adverbs, for example `honestly`, `obviously`, `clearly`
- process narration, for example `let me`, `I will`, `now we`, `here we`
- stalling phrases, user validation phrases, and self-blame phrases
- noun metaphors, for example `guardrail`, `footgun`, `happy path`,
  `silver bullet`
- editorializing adjectives, for example `honest`, `hacky`, `clever`,
  `clean fix`, `real solution`
- narrative, contrast, template, design, and short-answer frames
- `story`, `ground`, and `leg` as metaphors
- comma chains with `then`, `but`, `so`, and `-ing` clauses
- comment narration, for example `this ensures`, `note that`,
  `make sure to`
- banned words, for example `fails loudly`, `spearheaded`, `crutch`
- the container verb `carry`
- LLM vocabulary, for example `pivotal`, `crucial`, `tapestry`,
  `streamline`, `empower`
- chat openers at the start of a line, for example `Sure`, `Certainly`,
  `Great question`
- chat closers, for example `hope this helps`, `feel free to`
- chat assistant voice, for example `as an AI`, `my training data`
- contrast cliches, for example `not just X but Y` and `X, not Y:`
- rhetorical questions with an answer, for example `The catch? A race.`
- list items that start with a bold label or with an emoji
- dramatic failure verbs, for example `blows up`, `falls over`,
  `chokes on`
- parenthetical asides that start with `and`, `but`, or `plus`
- talk about the change under review, for example `no longer`,
  `for now`, `this PR`, `quick fix`, and `Previously` at the start of a
  sentence
- quoted error messages, for example `"Invalid header"`
- comments that describe the code at the start of a line, for example
  `Loop over`, `This function`, `Sets the`

The check also reads the shape of each block. A paragraph is a run of
consecutive lines with no blank line. Headings, tables, and fenced code
end a paragraph. A list item starts a new paragraph. Inline code and
URLs count as one word each. The shape findings are:

- a sentence with more than 25 words
- a paragraph with more than 120 words or more than 6 sentences
- a line that ends on a word that cannot end a phrase, for example
  `the`, `of`, or `and`, when the next line continues the paragraph
- 3 or more paragraphs in a row with almost the same word count
- 4 or more sentences in one paragraph with almost the same word count

Each shape finding counts as one match on the line where it starts.

The new pattern classes and the shape findings come from the
[nollm](https://github.com/NullVoxPopuli/nollm) rule list. The sentence
and paragraph limits come from ASD-STE100.

The check ignores inline code in backticks, URLs, and Credo directive
comments. In doc strings, it also ignores blank lines, fenced code
blocks, and lines with an indent of 4 spaces or more. The indent rule
skips doctests and Markdown code blocks. The check does not scan
`@moduledoc false` or doc attributes with only options, for example
`@doc since: "1.0"`.

Flagged example:

```elixir
# This ensures that we don't leak the socket, keep in mind.
def helper, do: :ok
```

Preferred form:

```elixir
# The socket closes in terminate/2. A leak here blocks the port.
def helper, do: :ok
```

Default messages:

```text
Too many LLMisms and non-human text in comments: 3 found in 1 line, limit 2 per 10 lines (contraction, filler phrase, comment narration)
Too many LLMisms and non-human text in docs: 3 found in 2 lines, limit 2 per 10 lines (word with no fact)
```

The extended explanation from `mix credo explain` lists the writing rules
for comments and docs.

### NoLLMismsInMarkdown

Default severity: readability warning. The LLMism findings do not change
the exit status of `mix credo`. A file that is not UTF-8 text fails the
build. See below.

The plugin does not enable this check by default. See the installation
section for the `llmisms_in_markdown` plugin option.

This check scans the Markdown files of the project with the same patterns,
shape checks, and limit as `NoLLMismsInComments`. Each heading starts a new
section. The text before the first heading is one section. The check
reports a section when the count of matches is above the limit for the
section size. The check reports one issue per section at most.

The check uses the `:mdex` package to parse the files. It does not scan
code blocks, HTML blocks, HTML comments, front matter, or blank lines.
Indented lines inside list items are list text, not code. If `:mdex` is
not available, the check shows a warning and reports no issues.

A file that is not UTF-8 text gets an issue in the warning category. That
issue changes the exit status of `mix credo`, so the build fails. The
message gives the first line with bytes that are not UTF-8:

```text
Markdown file is not UTF-8 text: line 3 has bytes that are not UTF-8
```

Params:

| Param            | Default                                             | Meaning                                         |
| ---------------- | --------------------------------------------------- | ----------------------------------------------- |
| `paths`          | `["**/*.md"]`                                       | The glob patterns of the Markdown files to scan. |
| `excluded_paths` | `["deps/**", "_build/**", "cover/**", "tmp/**", "**/node_modules/**"]` | The glob patterns of the Markdown files to skip. |
| `max_llmisms`    | 2                                                   | The number of matches that `window_lines` lines can contain. |
| `window_lines`   | 10                                                  | The number of lines that `max_llmisms` applies to. |

The patterns are relative to the directory where `mix credo` runs. The
`**` pattern does not match hidden directories, for example `.github/`.
To scan a hidden directory, add a pattern for it, for example
`".github/**/*.md"`.

The Markdown files are not Elixir source files. Credo does not run its
other checks on them. After the analysis, the plugin adds the Markdown
files with issues to the Credo file list. Credo needs that list to print
the source line of an issue in `--verbose` mode. Thus, keep `Llamex` in
the `plugins` list when you configure this check in `checks.extra`.

Default message:

```text
Too many LLMisms and non-human text in markdown: 3 found in 2 lines, limit 2 per 10 lines (word with no fact)
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
- `NoLLMismsInComments` and `NoLLMismsInMarkdown` are word list scans with
  a few shape checks. They do not detect metaphors outside their lists or
  passive voice.
- `NoLLMismsInMarkdown` scans the Markdown files on every `mix credo` run,
  also when the command names one source file.
