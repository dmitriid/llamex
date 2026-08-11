# What

A suite of Credo plugins that catch and fix issues introduced by various LLMs.

Each issue available in its own module, so that users can mix and match whatever part of code cleanup they want.

## Project Status

This project is vibe-coded. An AI coding agent wrote most of the code with little user input. We tested the checks on real Elixir projects, but this does not guarantee correct results in every project. Review each finding before you change code. Your results can vary (YMMV).

## Llamex.NoOneLiners

Catches stupid useless redundant one-liners left after LLM refactorings.

Default: error
Message: Redundant one-line wrapper. Replace with direct call

Examples:

```
## Functionality moved to a re-usable helper, the function is left behind with a useless single-line call
def search_for_record(id), do: Search.search_for_record(id)

## Same, just code shpe is different
def search_for_record(id), 
    do: Search.search_for_record(id)


## Same, just code shape is different
do search_for_record(id) do
    Search.search_for_record(id)
end

## Similar, helper is called, it's value is unused, a bogus structure is returned
do mark_invalid(id) do
    Search.mark_record_as_invalid!(id)
    {:ok, :done}
end

## Similar, helper is called, it's value is returned directly
do get_record(id) do
    value = Search.get_one_record!(id)
    {:ok, value}
end

```

Exceptions to the rule:

```
## Wrapper is catching potential failures.
## Could be a warning or info in this case, as this almost always means that we need to pattern match on a non-craching version  
do search_for_record(id) do
    Search.search_for_record!(id)
rescue
    ...
end


## handle_* functions delegate calls to common modules, re-usable components etc.
## This is fine

def handle_event("search:" <> evt, params, socket), do:
    Search.handle_input(evt, params, socket)
```

## Llamex.NoAdHocAshQueries

Catches ad-hoc queries, or ad-hoc options passed to queries when all queries must go through domain interfaces

Default: warning
Message: Avoid ad-hoc queries. Use domain interfaces instead

Examples:

```
## we call for_create, for_update, for_read etc. functiions, or any functions defined on Ash or Ash.* modules
def create_record(id, params) do:
    Helpdesk.Support.Ticket
    |> Ash.Changeset.for_create(:open, %{subject: "My mouse won't click!"})
    |> Ash.create!()
end

## we call interface functions, but pass in ad-hoc options in-place
def get_records_for_user(id) do
    Helpdesk.Support.get_user_records!(
        id,
        [
            load: [:comments, :statues, :related],
            offset: 20
        ]
    )
end
```

Exceptions to the rule:

```
## Ash.count and similar aggregate queries (max, min, sum, avg) are allowed on read queries

def no_of_records() do
    Helpdesk.Support.list_all_tickets()
    |> Ash.count!()
end

## Any module that has "use Ash.*" is allowed adhoc queries *except* domains
## that is, modules implementing changesets, loads, calculations, aggregates, resources etc. are allowed ad-hoc queries
## e.g.

defmodule Sleever.Sleeves.Changes.SetSourceSubmitter do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: %{id: actor_id}}) do
    ## whatever, because it has "use Ash.Resource.Change"
  end
end

```

## Llamex.ConsistentInterfaces

Catches deviations between interface method names exposed on the domain and action names in referenced resources.
Additionally catches redundant argument passing

Default: warning
Message: Keep interface names consistent with action names. Avoid redundant arg passing

Example:

```
resource Sleever.Sleeves.CardSize do
    # interface name and action name differ
    define :suggest_card_size_matches, action: :list_and_suggest_matched_cards, args: [:input]

    # if interface name fully matches action name on the resource, usually we don't need to change the shape of args
    # action needs to be checked to see if arg input is the same
    define :create_or_link_card_size_source, args: [:input]
end
```

## Llamex.NoDBWorkInMemory

The most complex one, may require tracing function calls back from the call site. Catches LLMs continuously lifting the entire
database into memory and filtering or searching through the entire dataset in memory via Enum.* or List.* functions

Default: error
Message: Do not operate on the whole dataset in memory. Use DB queries via resources

Example:

```

def show_invalid_records() do
    books = Books.get_all_books!()

    invalid_records = books 
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&.status == :invalid)
end
```

Note: the reading of DB doesn't necessarily happen in the same function as the Enum/List handling. The high-level lookup should be something like:

```
Enum/List handling found
  |
Find var on which it's operating
  | 
If var is fetched from another var (e.g. books.sources), switch to tracing this parent var
  |
If var comes from function params, find the caller and retrace from there
  |
If var comes from a call to a resource or to a domain interface, stop, we definitely get it from DB, error
```

note: for this particular case we need an opt-out mechanism with a module and/or function attribute somethign like @llamex.db_work_in_memory_allowed
because sometimes this is justified. See how credo handles this


# Additional considerations:

- use Elixir AST for code waling and Spark for handling Ash modules
- common functionality like code walking etc. must be shared. Credo likely provides some tools as well
    - e.g. look into project config first do discover which interfaces exit, and have them at the ready, instead of scanning the whole project to find them. 
      most of the tasks will require knowing which resources, interfaces, custom changesets etc. exist. 
- as much work in parallel as possible, since we don't want to wait for the whole project to be processed sequentially
    - for tasks like NoAdHocAshQueries, if the project has a *_web folder, prioritise process that one first 
- use mix.igniter to install deps
- prefer integration tests

There are some mix tasks that handle ad-hoc ash queries e.g. in ../sleever, but you can re-implement them from scratch. You can also freely re-use available Credo
or ExDNA tooling (and even install them to inspect their code), or approaches. 

This is a Credo plugin and will be used as such.
