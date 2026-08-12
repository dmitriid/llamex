defmodule Llamex.ChecksTest do
  use ExUnit.Case, async: true

  alias Credo.SourceFile
  alias Llamex.Credo.AddChecks

  test "exposes the shipped check modules" do
    assert Llamex.checks() == [
             Llamex.Check.NoOneLiners,
             Llamex.Check.NoAdHocAshQueries,
             Llamex.Check.ConsistentInterfaces,
             Llamex.Check.NoDBWorkInMemory,
             Llamex.Check.NoAuthorizeBypass,
             Llamex.Check.NoSelfInLiveViews
           ]
  end

  test "registers all checks through the Credo plugin entry point" do
    exec =
      Credo.Execution.build([])
      |> Credo.Execution.set_initializing_plugin(Llamex)
      |> Llamex.init()

    validate_config_tasks = exec.pipeline_map[Credo.Execution][:validate_config]

    assert {Llamex.Credo.AddChecks, []} in validate_config_tasks
  end

  test "injects plugin checks when a project config uses checks.enabled" do
    exec = %Credo.Execution{
      checks: %{
        enabled: [{Credo.Check.Warning.IoInspect, []}],
        disabled: []
      }
    }

    exec = AddChecks.call(exec, [])

    assert {Llamex.Check.NoOneLiners, [skip_tests: true]} in exec.checks.enabled
    assert {Llamex.Check.NoAdHocAshQueries, [skip_tests: true]} in exec.checks.enabled
    assert {Llamex.Check.ConsistentInterfaces, [skip_tests: true]} in exec.checks.enabled
    assert {Llamex.Check.NoDBWorkInMemory, [skip_tests: true]} in exec.checks.enabled
    assert {Llamex.Check.NoAuthorizeBypass, [skip_tests: true]} in exec.checks.enabled
    assert {Llamex.Check.NoSelfInLiveViews, [skip_tests: true]} in exec.checks.enabled
  end

  test "plugin-level skip_tests config is propagated to injected checks" do
    exec = %Credo.Execution{
      plugins: [{Llamex, [skip_tests: false]}],
      checks: %{
        enabled: [],
        disabled: []
      }
    }

    exec = AddChecks.call(exec, [])

    assert {Llamex.Check.NoAdHocAshQueries, [skip_tests: false]} in exec.checks.enabled
  end

  defp issues(check, source, params \\ []) do
    source
    |> SourceFile.parse("lib/sample.ex")
    |> check.run(params)
  end

  defp test_file_issues(check, source, params \\ []) do
    source
    |> SourceFile.parse("test/sample_test.exs")
    |> check.run(params)
  end

  defp mix_task_issues(check, source, params \\ []) do
    source
    |> SourceFile.parse("lib/mix/tasks/sample.ex")
    |> check.run(params)
  end

  defp web_file_issues(check, source, params \\ []) do
    source
    |> SourceFile.parse("lib/sample_web/error_html.ex")
    |> check.run(params)
  end

  defp messages(issues), do: Enum.map(issues, & &1.message)

  test "all checks skip test files by default" do
    sources = [
      {Llamex.Check.NoOneLiners,
       """
       defmodule SampleTest do
         def helper(id), do: Search.get!(id)
       end
       """},
      {Llamex.Check.NoAdHocAshQueries,
       """
       defmodule SampleTest do
         def helper do
           Resource |> Ash.Query.for_read(:read) |> Ash.read!()
         end
       end
       """},
      {Llamex.Check.ConsistentInterfaces,
       """
       defmodule SampleDomainTest do
         use Ash.Domain

         resources do
           resource Resource do
             define :list_things, action: :search_things
           end
         end
       end
       """},
      {Llamex.Check.NoDBWorkInMemory,
       """
       defmodule SampleTest do
         def helper do
           Things.list_things!() |> Enum.filter(& &1.active)
         end
       end
       """},
      {Llamex.Check.NoAuthorizeBypass,
       """
       defmodule SampleTest do
         def helper(id) do
           Support.get_ticket!(id, authorize?: false)
         end
       end
       """},
      {Llamex.Check.NoSelfInLiveViews,
       """
       defmodule SampleTest do
         use SampleWeb, :live_view

         def mount(_params, _session, socket) do
           send(self(), :load)
           {:ok, socket}
         end
       end
       """}
    ]

    for {check, source} <- sources do
      assert [] = test_file_issues(check, source)
    end
  end

  test "checks can opt back into test files" do
    source = """
    defmodule SampleTest do
      def helper do
        Resource |> Ash.Query.for_read(:read) |> Ash.read!()
      end
    end
    """

    assert [_ | _] = test_file_issues(Llamex.Check.NoAdHocAshQueries, source, skip_tests: false)
  end

  test "all checks skip Mix task files by default" do
    source = """
    defmodule Mix.Tasks.Sample do
      use Mix.Task

      def run(_args) do
        Resource |> Ash.Query.for_read(:read) |> Ash.read!()
      end
    end
    """

    for check <- Llamex.checks() do
      assert [] = mix_task_issues(check, source)
    end
  end

  describe "NoOneLiners" do
    test "flags trivial one-line and assign-return wrappers" do
      source = """
      defmodule Sample do
        def search_for_record(id), do: Search.search_for_record(id)

        def get_record(id) do
          value = Search.get_one_record!(id)
          {:ok, value}
        end
      end
      """

      issues = issues(Llamex.Check.NoOneLiners, source)

      assert length(issues) == 2
      assert Enum.all?(messages(issues), &String.contains?(&1, "Redundant one-line wrapper"))
    end

    test "allows callbacks and wrappers with rescue" do
      source = """
      defmodule Sample do
        def handle_event("search:" <> event, params, socket) do
          Search.handle_input(event, params, socket)
        end

        def search_for_record(id) do
          Search.search_for_record!(id)
        rescue
          error -> {:error, error}
        end
      end
      """

      assert [] = issues(Llamex.Check.NoOneLiners, source)
    end

    test "allows pipe chains that do local work" do
      source = """
      defmodule Sample do
        def core_requirement_exists?(attrs, actor) do
          attrs.game_id
          |> Sleeves.list_current_game_card_requirements_for_game!(actor: actor)
          |> Enum.any?(fn row ->
            row.card_size_id == attrs.card_size_id and row.source_system == :core
          end)
        end
      end
      """

      assert [] = issues(Llamex.Check.NoOneLiners, source)
    end

    test "allows conditional functions" do
      source = """
      defmodule Sample do
        defp wait_or_timeout(task_uid, task, opts, interval, deadline) do
          if System.monotonic_time(:millisecond) >= deadline do
            {:error, {:timeout, task}}
          else
            Process.sleep(interval)
            do_wait_for_task(task_uid, opts, interval, deadline)
          end
        end
      end
      """

      assert [] = issues(Llamex.Check.NoOneLiners, source)
    end

    test "allows functions that return data" do
      source = """
      defmodule Sample do
        defp exception_to_error(error, stage, adapter, source_ref, candidate) do
          %{
            source_adapter: inspect(adapter),
            source_system: Map.get(candidate, :source_system),
            source_url: to_string(source_ref),
            parse_stage: to_string(stage),
            exception_class: "UnknownSourceError",
            exception_message: inspect(error)
          }
        end

        defp tags, do: [:core, :community]

        defp coordinates do
          {10, 20}
        end

        defp label(name) do
          "source:\#{name}"
        end
      end
      """

      assert [] = issues(Llamex.Check.NoOneLiners, source)
    end

    test "allows callback-style collection side effects" do
      source = """
      defmodule Sample do
        defp persist_errors(errors, adapter, actor, attempt) do
          Enum.each(errors, fn error ->
            error = normalize_error(error, adapter)

            Sleeves.create_source_error!(
              %{
                source_adapter: Map.get(error, :source_adapter, inspect(adapter)) |> to_string(),
                query_text: "sleeve product catalog",
                retry_count: Map.get(error, :retry_count, attempt),
                occurred_at: DateTime.utc_now()
              },
              actor: actor
            )
          end)
        end
      end
      """

      assert [] = issues(Llamex.Check.NoOneLiners, source)
    end

    test "allows calls that transform or add arguments" do
      source = """
      defmodule Sample do
        def search(id) do
          Search.find(to_string(id))
        end

        def get_record(id) do
          value = Search.get_one_record!(to_string(id))
          {:ok, value}
        end

        def mark_invalid(id) do
          Search.mark_record_as_invalid!(id, source: :admin)
          {:ok, :done}
        end
      end
      """

      assert [] = issues(Llamex.Check.NoOneLiners, source)
    end

    test "allows multi-clause normalization helpers" do
      source = """
      defmodule Sample do
        defp normalize_atom(nil), do: nil
        defp normalize_atom(value) when is_atom(value), do: value
        defp normalize_atom(value), do: String.to_existing_atom(value)
      end
      """

      assert [] = issues(Llamex.Check.NoOneLiners, source)
    end

    test "allows render callbacks in web modules" do
      source = """
      defmodule SampleWeb.ErrorHTML do
        def render(template, _assigns) do
          Phoenix.Controller.status_message_from_template(template)
        end
      end
      """

      assert [] = web_file_issues(Llamex.Check.NoOneLiners, source)
    end

    test "allows impl callbacks" do
      source = """
      defmodule SampleAdapter do
        @impl true
        def fetch_details(source_id_or_url) do
          source_adapter(source_id_or_url, []).fetch_details(source_id_or_url)
        end
      end
      """

      assert [] = issues(Llamex.Check.NoOneLiners, source)
    end

    test "allows dependency-injection dispatch wrappers" do
      source = """
      defmodule SampleAdapter do
        @impl true
        def fetch_details(source_id_or_url) do
          source_adapter(source_id_or_url, []).fetch_details(source_id_or_url)
        end

        def fetch_details(source_id_or_url, options) do
          source_adapter(source_id_or_url, options).fetch_details(source_id_or_url)
        end
      end
      """

      assert [] = issues(Llamex.Check.NoOneLiners, source)
    end

    test "allows function-level one-liner opt-out attribute" do
      source = """
      defmodule SampleAdapter do
        @llamex_one_liner_allowed true
        def fetch_details(source_id_or_url, options) do
          source_adapter(source_id_or_url, options).fetch_details(source_id_or_url)
        end
      end
      """

      assert [] = issues(Llamex.Check.NoOneLiners, source)
    end
  end

  describe "NoAdHocAshQueries" do
    test "flags direct query and execution APIs outside Ash implementation modules" do
      source = """
      defmodule Sample do
        def create_ticket(params) do
          Helpdesk.Support.Ticket
          |> Ash.Changeset.for_create(:open, params)
          |> Ash.create!()
        end
      end
      """

      assert [first | _] = issues(Llamex.Check.NoAdHocAshQueries, source)
      assert first.message =~ "Avoid ad-hoc queries"
    end

    test "allows aggregate terminal calls and Ash implementation modules" do
      aggregate = """
      defmodule Sample do
        def count_tickets do
          Helpdesk.Support.list_all_tickets()
          |> Ash.count!()
        end
      end
      """

      implementation_module = """
      defmodule Sample.Change do
        use Ash.Resource.Change

        def change(changeset, _opts, %{actor: %{id: actor_id}}) do
          Ash.Changeset.force_change_attribute(changeset, :submitter_id, actor_id)
        end
      end
      """

      assert [] = issues(Llamex.Check.NoAdHocAshQueries, aggregate)
      assert [] = issues(Llamex.Check.NoAdHocAshQueries, implementation_module)
    end

    test "allows direct Ash usage inside modules that use Ash modules" do
      source = """
      defmodule Sample.Domain do
        use Ash.Domain

        def debug_query do
          Resource
          |> Ash.Query.for_read(:read)
          |> Ash.read!()
        end
      end
      """

      assert [] = issues(Llamex.Check.NoAdHocAshQueries, source)
    end

    test "flags inline ad-hoc query options on domain interface calls" do
      source = """
      defmodule Sample do
        def get_records_for_user(id) do
          Helpdesk.Support.get_user_records!(id, load: [:comments], offset: 20)
        end
      end
      """

      assert [issue] = issues(Llamex.Check.NoAdHocAshQueries, source)
      assert issue.message =~ "Avoid ad-hoc queries"
    end
  end

  describe "ConsistentInterfaces" do
    test "flags interface defines whose name differs from the action" do
      source = """
      defmodule Helpdesk.Support do
        use Ash.Domain

        resources do
          resource Helpdesk.Support.Ticket do
            define :suggest_card_size_matches,
              action: :list_and_suggest_matched_cards,
              args: [:input]
          end
        end
      end
      """

      assert [issue] = issues(Llamex.Check.ConsistentInterfaces, source)
      assert issue.message =~ "suggest_card_size_matches"
      assert issue.message =~ "list_and_suggest_matched_cards"
    end

    test "allows matching interface and action names" do
      source = """
      defmodule Helpdesk.Support do
        use Ash.Domain

        resources do
          resource Helpdesk.Support.Ticket do
            define :list_and_suggest_matched_cards,
              action: :list_and_suggest_matched_cards,
              args: [:input]
          end
        end
      end
      """

      assert [] = issues(Llamex.Check.ConsistentInterfaces, source)
    end
  end

  describe "NoDBWorkInMemory" do
    test "flags Enum work on values from Ash-style domain interfaces" do
      source = """
      defmodule Sample do
        alias Helpdesk.Support.Books

        def show_invalid_records do
          books = Books.get_all_books!()

          books
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(&(&1.status == :invalid))
        end
      end
      """

      assert [issue | _] = issues(Llamex.Check.NoDBWorkInMemory, source)
      assert issue.message =~ "Do not operate on the whole dataset in memory"
      assert issue.message =~ "Books.get_all_books!"
    end

    test "honors the Llamex opt-out attribute" do
      source = """
      defmodule Sample do
        @llamex_db_work_in_memory_allowed true

        def show_invalid_records do
          Books.get_all_books!()
          |> Enum.filter(&(&1.status == :invalid))
        end
      end
      """

      assert [] = issues(Llamex.Check.NoDBWorkInMemory, source)
    end

    test "allows scoped domain interface results" do
      source = """
      defmodule Sample do
        alias Helpdesk.Support

        def find_requirement(game_id, attrs, actor) do
          Support.list_current_game_card_requirements_for_game!(game_id, actor: actor)
          |> Enum.find(&(&1.card_size_id == attrs.card_size_id))
        end
      end
      """

      assert [] = issues(Llamex.Check.NoDBWorkInMemory, source)
    end

    test "allows in-memory work inside Ash implementation modules" do
      source = """
      defmodule Sample.Calculation do
        use Ash.Resource.Calculation
        alias Helpdesk.Support.Books

        def calculate(_records, _opts, _context) do
          Books.get_all_books!()
          |> Enum.filter(& &1.active)
        end
      end
      """

      assert [] = issues(Llamex.Check.NoDBWorkInMemory, source)
    end
  end

  describe "NoAuthorizeBypass" do
    test "flags authorize?: false on direct Ash calls" do
      source = """
      defmodule Sample do
        def create_ticket(params) do
          Ash.create!(changeset, authorize?: false)
        end
      end
      """

      assert [issue] = issues(Llamex.Check.NoAuthorizeBypass, source)
      assert issue.message =~ "Do not use authorize?: false"
      assert issue.message =~ "actor: %{system: name}"
      refute issue.message =~ "{system,"
    end

    test "flags authorize?: false on Ash.Changeset calls" do
      source = """
      defmodule Sample do
        def create_ticket(params) do
          Ash.Changeset.for_create(Resource, :create, params, authorize?: false)
        end
      end
      """

      assert [issue] = issues(Llamex.Check.NoAuthorizeBypass, source)
      assert issue.message =~ "Do not use authorize?: false"
    end

    test "flags authorize?: false on Ash.Query calls" do
      source = """
      defmodule Sample do
        def list_tickets do
          Ash.Query.for_read(Resource, :read, authorize?: false)
        end
      end
      """

      assert [issue] = issues(Llamex.Check.NoAuthorizeBypass, source)
      assert issue.message =~ "Do not use authorize?: false"
    end

    test "flags authorize?: false on domain interface calls" do
      source = """
      defmodule Sample do
        def get_ticket(id) do
          Support.get_ticket!(id, authorize?: false)
        end
      end
      """

      assert [issue] = issues(Llamex.Check.NoAuthorizeBypass, source)
      assert issue.message =~ "Do not use authorize?: false"
    end

    test "allows calls without authorize?: false" do
      source = """
      defmodule Sample do
        def get_ticket(id, actor) do
          Support.get_ticket!(id, actor: actor)
        end
      end
      """

      assert [] = issues(Llamex.Check.NoAuthorizeBypass, source)
    end

    test "allows authorize?: true" do
      source = """
      defmodule Sample do
        def get_ticket(id, actor) do
          Support.get_ticket!(id, actor: actor, authorize?: true)
        end
      end
      """

      assert [] = issues(Llamex.Check.NoAuthorizeBypass, source)
    end

    test "ignores local function calls with authorize?: false" do
      source = """
      defmodule Sample do
        def get_ticket(id) do
          fetch_ticket(id, authorize?: false)
        end
      end
      """

      assert [] = issues(Llamex.Check.NoAuthorizeBypass, source)
    end

    test "skips test files by default" do
      source = """
      defmodule SampleTest do
        def helper(id) do
          Support.get_ticket!(id, authorize?: false)
        end
      end
      """

      assert [] = test_file_issues(Llamex.Check.NoAuthorizeBypass, source)
    end

    test "flags authorize?: false mixed with other options" do
      source = """
      defmodule Sample do
        def get_ticket(id) do
          Support.get_ticket!(id, actor: nil, authorize?: false, load: [:comments])
        end
      end
      """

      assert [issue] = issues(Llamex.Check.NoAuthorizeBypass, source)
      assert issue.message =~ "Do not use authorize?: false"
    end
  end

  describe "NoSelfInLiveViews" do
    test "flags self calls in Phoenix LiveView modules" do
      source = """
      defmodule SampleWeb.HomeLive do
        use Phoenix.LiveView

        def mount(_params, _session, socket) do
          send(self(), :load)
          {:ok, socket}
        end
      end
      """

      assert [issue] = issues(Llamex.Check.NoSelfInLiveViews, source)

      assert issue.message ==
               "Do not use self() in Phoenix LiveViews. Use start_async/3 or assign_async/3, and handle the result with built-in Phoenix functions. Use Task or supervisor trees only in rare cases."
    end

    test "flags self calls in project macro LiveView modules" do
      source = """
      defmodule SampleWeb.HomeLive do
        use SampleWeb, :live_view

        def handle_event("refresh", _params, socket) do
          Process.send_after(self(), :refresh, 100)
          {:noreply, socket}
        end
      end
      """

      assert [issue] = issues(Llamex.Check.NoSelfInLiveViews, source)
      assert issue.trigger == "self"
    end

    test "allows self calls outside LiveView modules" do
      source = """
      defmodule Sample.Worker do
        def run do
          send(self(), :load)
        end
      end
      """

      assert [] = issues(Llamex.Check.NoSelfInLiveViews, source)
    end

    test "allows LiveView modules without self calls" do
      source = """
      defmodule SampleWeb.HomeLive do
        use SampleWeb, :live_view

        def mount(_params, _session, socket) do
          {:ok, assign_async(socket, :stats, fn -> {:ok, %{stats: 1}} end)}
        end
      end
      """

      assert [] = issues(Llamex.Check.NoSelfInLiveViews, source)
    end
  end
end
