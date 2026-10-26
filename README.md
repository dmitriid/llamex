# Llamex

Llamex is a Credo plugin for Elixir projects. It checks code for problems
that AI coding tools often cause. It reports problems but does not change
code.

Llamex includes nine checks. Seven checks are active by default:

| Check | What it reports |
| --- | --- |
| `NoOneLiners` | Functions that only call another function or put its result in a tuple. |
| `NoAdHocAshQueries` | Ash queries outside resource actions. |
| `ConsistentInterfaces` | Ash interface names that differ from their action names. |
| `NoDBWorkInMemory` | Operations on database records in memory. |
| `NoAuthorizeBypass` | Calls that use `authorize?: false`. |
| `NoSelfInLiveViews` | Calls to `self()` in Phoenix LiveViews. |
| `NoMultipleAssigns` | More than three separate `assign` calls in a pipe chain. |

Two checks are optional:

| Check | What it reports |
| --- | --- |
| `NoLLMismsInComments` | Unclear or unnecessary text in comments, doc strings, and test names. |
| `NoLLMismsInMarkdown` | Unclear or unnecessary text in Markdown files. |

Each check module uses the prefix `Llamex.Check`.

## Project status

An AI coding tool wrote most of this project with little user input.
Tests on Elixir projects do not prove that all results are correct.

Check each reported problem before you change your code.

The [project description](project-description.md) explains the original
requirements for the checks.

## Installation

1. Clone Llamex next to your project:

   ```sh
   git clone https://github.com/dmitriid/llamex.git
   ```

2. Add Llamex to the dependencies in your project:

   ```elixir
   def deps do
     [
       {:llamex, path: "../llamex", only: [:dev, :test], runtime: false}
     ]
   end
   ```

3. Run this command in your project directory:

   ```sh
   mix deps.get
   ```

4. Add `Llamex` to the `plugins` list in `.credo.exs`:

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

5. Run Credo:

   ```sh
   mix credo
   ```

The plugin adds the seven default checks after Credo reads the project
configuration. It also supports configurations that use `checks.enabled`.

### Test files and Mix tasks

By default, the checks skip these files:

- Files under `test/`
- Files with names that end in `_test.exs`
- Files under `lib/mix/tasks/`

To include these files, set `skip_tests` to `false`:

```elixir
plugins: [
  {Llamex, [skip_tests: false]}
]
```

All checks except `NoLLMismsInMarkdown` support `skip_tests`.

### Comments and doc strings

The `llmisms_in_comments` option controls `NoLLMismsInComments`. The value
`true` enables the check with its default parameters. A keyword list
enables the check with the specified parameters.

To use the default parameters, add this plugin option:

```elixir
plugins: [
  {Llamex, [llmisms_in_comments: true]}
]
```

To change the parameters, use a keyword list:

```elixir
plugins: [
  {Llamex, [llmisms_in_comments: [max_llmisms: 1, window_lines: 5]]}
]
```

### Markdown files

The `llmisms_in_markdown` option controls `NoLLMismsInMarkdown`. It accepts
`true` or a keyword list, as `llmisms_in_comments` does. This check requires
`:mdex`, which is an optional dependency of Llamex.

1. Add `:mdex` to the dependencies in your project:

   ```elixir
   {:mdex, "~> 0.14", only: [:dev, :test], runtime: false}
   ```

2. Run this command in your project directory:

   ```sh
   mix deps.get
   ```

3. Enable the Markdown check in `.credo.exs`:

   ```elixir
   plugins: [
     {Llamex, [llmisms_in_comments: true, llmisms_in_markdown: true]}
   ]
   ```

To select which Markdown files to check, set `paths`:

```elixir
plugins: [
  {Llamex, [llmisms_in_markdown: [paths: ["*.md", "docs/**/*.md"]]]}
]
```

### Individual checks

To use only selected Elixir checks, add their modules to `checks.extra`:

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

The Markdown check also requires the `Llamex` plugin to print source lines
in Credo output. Its description below explains this requirement.

## Checks

### NoOneLiners

Credo category: `:refactor`. Priority: `:high`.

This check reports functions that add a call without an operation that
requires a separate function. It detects these cases:

- The function only calls another function.
- The function assigns the result of a call and returns `{:ok, result}`.
- The function ignores the result of a call and returns a success tuple.

The check reports these functions:

```elixir
def search_for_record(id), do: Search.search_for_record(id)

def get_record(id) do
  value = Search.get_one_record!(id)
  {:ok, value}
end
```

The check skips these functions:

- Functions with more than one clause
- Functions with guards or patterns that restrict arguments
- Functions with `rescue`, `catch`, or `after` blocks
- Callbacks with names that start with `handle_`, such as `handle_event/3`
- `render` functions in web modules
- Functions with an `@impl` attribute

To allow a function that must remain separate, add this attribute before it:

```elixir
@llamex_one_liner_allowed true
```

### NoAdHocAshQueries

Credo category: `:warning`. Priority: `:normal`.

This check reports direct Ash API calls in application modules. It checks
calls to these modules:

- `Ash`
- `Ash.Query`
- `Ash.Changeset`

It also reports domain interface calls with these query options:

- `load`
- `filter` or `filters`
- `sort`
- `query`

The check reports these calls:

```elixir
Ticket
|> Ash.Changeset.for_create(:open, params)
|> Ash.create!()

Support.get_user_records!(id, load: [:comments])
```

The check permits pagination options:

- `page`
- `limit`
- `offset`

It also permits aggregate calls, such as `Ash.count!/1`. It skips Ash
implementation modules, such as modules that use `Ash.Resource.*`.

- Put query options in the resource action.
- Use domain interfaces for application calls.

### ConsistentInterfaces

Credo category: `:warning`. Priority: `:normal`.

This check reports Ash domain interfaces with names that differ from
their action names. It reports this declaration:

```elixir
define :suggest_card_size_matches,
  action: :list_and_suggest_matched_cards,
  args: [:input]
```

Use the same name for the interface and the action.

### NoDBWorkInMemory

Credo category: `:warning`. Priority: `:high`.

This check reports operations on collections that appear to come from a
database. It checks calls to these modules:

- `Enum`
- `List`
- `Stream`

The check follows values within the current file to find an Ash call or
a domain interface call. Each reported problem includes the source call.

The check reports this code:

```elixir
Books.get_all_books!()
|> Enum.reject(&is_nil/1)
|> Enum.filter(&(&1.status == :invalid))
```

Move the operation into the resource action so that the database does the
work.

To allow operations on the full collection in memory, add this attribute:

```elixir
@llamex_db_work_in_memory_allowed true
```

Credo comments that disable the check also prevent reports.

### NoAuthorizeBypass

Credo category: `:warning`. Priority: `:high`.

This check reports `authorize?: false` in Ash calls and domain interface
calls. It includes calls to `Ash.Query` and `Ash.Changeset`.

The check reports these calls:

```elixir
Ash.create!(changeset, authorize?: false)
Support.get_ticket!(id, authorize?: false)
```

Pass the actor that started the action:

```elixir
Support.create_ticket!(params, actor: user)
```

For actions that a system process starts, pass a system actor:

```elixir
Support.create_ticket!(params, actor: %{system: :my_oban_job})
```

System processes include these examples:

- Oban jobs
- Database seed scripts
- Database migrations

### NoSelfInLiveViews

Credo category: `:warning`. Priority: `:high`.

This check reports local `self()` calls in Phoenix LiveView modules. It
recognizes `use Phoenix.LiveView` and project macros such as
`use MyAppWeb, :live_view`. It checks the module that contains each call.

The check reports this code:

```elixir
def mount(_params, _session, socket) do
  send(self(), :load)
  {:ok, socket}
end
```

1. Use `start_async/3` or `assign_async/3` for asynchronous work.
2. Use the Phoenix functions to process the result.

### NoMultipleAssigns

Credo category: `:readability`. This check does not change the exit status
of `mix credo`.

This check reports pipe chains with more than three `assign` calls that
each set one key. It reports this code:

```elixir
socket
|> assign(:tab, parse_tab(params["tab"]))
|> assign(:status, parse_status(params["status"]))
|> assign(:page, parse_page(params["page"]))
|> assign(:url_status, parse_status(params["url_status"]))
```

Use one `assign` call with a keyword list:

```elixir
assign(socket,
  tab: parse_tab(params["tab"]),
  status: parse_status(params["status"]),
  page: parse_page(params["page"]),
  url_status: parse_status(params["url_status"])
)
```

The `max_assigns` parameter sets the maximum number of separate calls.
The default value is 3.

### NoLLMismsInComments

Credo category: `:readability`. This check does not change the exit status
of `mix credo`. It is optional.

This check searches comments, doc strings, and test names for unnecessary
phrases and unclear text. It checks each block separately. Consecutive `#`
comment lines form one block.

Each doc string in these attributes also forms one block:

- `@moduledoc`
- `@doc`
- `@typedoc`
- `@shortdoc`

If `skip_tests` is `false`, the check also searches the test names in
test files. A test name is the text after `describe`, `test`, or
`property`. Each test name forms one block:

```elixir
describe "the cache" do
  test "returns nil for a missing file" do
```

The check ignores text in backticks.

To use code in a test name, put the code in backticks:

```elixir
test "returns nil after `rescue`" do
```

The limit is `max_llmisms` matches per `window_lines` lines. The default
limit is 2 matches per 10 lines. The permitted number of matches decreases
for shorter blocks:

| Block length | Permitted matches | First match above the limit |
| --- | --- | --- |
| 10 lines | 2 | Third match |
| 5 lines | 1 | Second match |
| 1 line | 0 | First match |

For longer blocks, the check examines each group of `window_lines`
consecutive lines. It reports one problem per block at most.

| Parameter | Default | Meaning |
| --- | --- | --- |
| `max_llmisms` | 2 | The permitted number of matches per group of lines. |
| `window_lines` | 10 | The number of lines per group. |
| `skip_tests` | `true` | Skip test files and Mix task files. |

To enable this check, set the `llmisms_in_comments` plugin option as shown
in the installation instructions.

To set parameters for the individual check, use `checks.extra`:

```elixir
checks: %{
  extra: [
    {Llamex.Check.NoLLMismsInComments, [max_llmisms: 1, window_lines: 5]}
  ]
}
```

#### Text patterns

The check searches for these forms. The examples identify text that the
check reports.

| Form | Examples |
| --- | --- |
| Punctuation | Em dashes and semicolons |
| Contractions | `don't`, `it's` |
| Modal verbs | `should`, `would`, `could`, `might`, `may` |
| Present perfect verbs | `has been`, `have changed` |
| Words without specific information | `simply`, `robust`, `seamless`, `leverage`, `elegant` |
| Latin abbreviations | `e.g.`, `i.e.` |
| Unnecessary phrases | `in order to`, `prior to`, `in the event that` |
| Unnecessary reminders or introductions | `worth noting`, `keep in mind`, `deep dive` |
| Verb metaphors | `rescues`, `nudges`, `swallows`, `wires up` |
| Container or status verbs | `hold`, `carry`, `stand` |
| Adverbs without specific information | `honestly`, `obviously`, `clearly` |
| Descriptions of the writer's process | `let me`, `I will`, `now we`, `here we` |
| Delays, agreement, or blame | `but wait`, `you are right`, `my mistake` |
| Noun metaphors | `guardrail`, `footgun`, `happy path`, `silver bullet`, `a gap in` |
| Adjectives that state opinions | `honest`, `hacky`, `clever`, `clean fix`, `serious issue` |
| Sentence patterns without specific information | `the real need behind`, `the pattern is:`, `short answer` |
| Template or design metaphors | `is a template for`, `is the design` |
| Other metaphors | `story`, `ground`, `leg`, `is dead`, `is a lie` |
| Long clause sequences | Commas with `then`, `but`, `so`, or an `-ing` clause |
| Unnecessary comment phrases | `this ensures`, `note that`, `make sure to` |
| Other prohibited words | `fails loudly`, `spearheaded`, `crutch` |
| Words common in AI text | `pivotal`, `crucial`, `tapestry`, `streamline`, `empower` |
| Chat introductions | `Sure`, `Certainly`, `Great question` at the start of a line |
| Chat conclusions | `hope this helps`, `feel free to` |
| Chat assistant phrases | `as an AI`, `my training data` |
| Contrast phrases | `not just X but Y`, `X, not Y:` |
| Questions with immediate answers | `The catch? A race.` |
| List item prefixes | A bold label or an emoji |
| Exaggerated failure verbs | `blows up`, `falls over`, `chokes on` |
| Extra comments in parentheses | Parentheses that start with `and`, `but`, or `plus` |
| Text about a code change | `no longer`, `for now`, `this PR`, `quick fix`, `Previously` |
| Quoted error messages | `"Invalid header"` |
| Comments that repeat the code | `Loop over`, `This function`, `Sets the` at the start of a line |

#### Sentence and paragraph limits

The check also reports these problems:

- A sentence contains more than 25 words.
- A paragraph contains more than 120 words or six sentences.
- At least four sentences in a paragraph have almost the same word count.

Each problem counts as one match on its first line. Inline code and URLs
each count as one word.

A paragraph consists of consecutive lines without a blank line. A list
item starts a new paragraph. These elements end a paragraph:

- Headings
- Tables
- Fenced code blocks

Some text patterns and paragraph checks come from the
[nollm rule list](https://github.com/NullVoxPopuli/nollm).

ASD-STE100 sets these limits for descriptions:

- 25 words per sentence
- Six sentences per paragraph

#### Text that the check skips

The check skips these elements:

- Inline code in backticks
- URLs
- Credo directive comments

In doc strings, it also skips these elements:

- Blank lines
- Fenced code blocks
- Lines with an indent of at least four spaces, such as doctests

The check skips `@moduledoc false` and attributes with only options, such
as `@doc since: "1.0"`.

#### Example

The check reports this comment:

```elixir
# This ensures that we don't leak the socket, keep in mind.
def helper, do: :ok
```

State the relevant behavior and its effect:

```elixir
# The socket closes in terminate/2. A leak here blocks the port.
def helper, do: :ok
```

The report includes the match count and the types of text that exceed
the limit. The explanation from `mix credo explain` includes the rules
for comments and doc strings.

### NoLLMismsInMarkdown

Credo category: `:readability`. Text style problems do not change the exit
status of `mix credo`. This check is optional.

This check uses the same text patterns and limits as `NoLLMismsInComments`.
Each heading starts a section. Text before the first heading forms a
separate section. The check reports one problem per section at most.

The check uses `:mdex` to parse Markdown files. If `:mdex` is absent, the
check prints a warning and reports no problems.

The check skips these elements:

- Code blocks
- HTML blocks and HTML comments
- Front matter
- Blank lines

The check includes indented text within list items.

Files must contain valid UTF-8 text. If a file contains invalid bytes,
the check reports a warning with the first affected line number. This
warning changes the exit status of `mix credo` and fails the build.

| Parameter | Default | Meaning |
| --- | --- | --- |
| `paths` | `["**/*.md"]` | File patterns to include. |
| `excluded_paths` | `["deps/**", "_build/**", "cover/**", "tmp/**", "**/node_modules/**"]` | File patterns to skip. |
| `max_llmisms` | 2 | The permitted number of matches per group of lines. |
| `window_lines` | 10 | The number of lines per group. |

File patterns are relative to the directory where you run `mix credo`.
The `**` pattern does not include hidden directories such as `.github/`.

To include a hidden directory, add a pattern such as `".github/**/*.md"`
to `paths`.

Credo runs its Elixir checks on Elixir files. The Llamex plugin adds
Markdown files with reported problems to the Credo file list after the
checks finish. Credo uses this list to print source lines in `--verbose`
output.

Keep `Llamex` in the `plugins` list when you add this check to
`checks.extra`.

## Limits

The code checks examine the abstract syntax tree of each source file.
They use code structure and function names to identify possible problems.
They do not require Ash or Spark metadata at runtime.

The checks cannot identify every problem in these cases:

- Calls between files
- Calls that select a module or function at runtime
- Generated code
- Complex macros

The text checks search for listed words and phrases. They also check
sentence and paragraph length. They do not detect passive voice or
metaphors outside their lists.

`NoLLMismsInMarkdown` checks Markdown files on each `mix credo` run. It
also checks them when the command specifies one Elixir file.
