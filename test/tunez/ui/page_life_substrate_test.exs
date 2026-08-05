defmodule Tunez.UI.PageLifeSubstrateTest do
  use ExUnit.Case, async: true

  test "the substrate ticks routed mounts once and leaves child mounts untouched" do
    session_id = Ash.UUID.generate()

    assert AshBlueprint.Info.supplied_page_life(Tunez.UI.ArtistIndexPage) ==
             {Tunez.UI.PageLifeDomain, :begin_page_life}

    assert AshBlueprint.Changes.BeginPageLife in change_modules(Tunez.UI.ArtistIndexPage, :mount)

    assert AshBlueprint.Info.supplied_page_life(Tunez.UI.AppShell) == nil
    refute AshBlueprint.Changes.BeginPageLife in change_modules(Tunez.UI.AppShell, :mount)

    assert {:ok, %{session_id: ^session_id}} =
             mount(Tunez.UI.ArtistIndexPage, session_id, :static)

    assert page_life(session_id) == nil

    assert {:ok, %{session_id: ^session_id}} =
             mount(Tunez.UI.ArtistIndexPage, session_id, :live)

    assert page_life(session_id) == 1

    assert {:ok, %{session_id: ^session_id}} =
             mount(Tunez.UI.AppShell, session_id, :live, %{signed_in?: false, email: ""})

    assert page_life(session_id) == 1
  end

  defp mount(resource, session_id, phase, input \\ %{}) do
    resource
    |> Ash.Changeset.for_create(:mount, input,
      context: %{session_id: session_id, ash_blueprint_mount_phase: phase},
      domain: Tunez.UI,
      upsert?: true,
      upsert_identity: :session_instance
    )
    |> Ash.create(domain: Tunez.UI)
  end

  defp page_life(session_id) do
    case Ash.get(Tunez.UI.PageLife, session_id,
           domain: Tunez.UI,
           not_found_error?: false
         ) do
      {:ok, nil} -> nil
      {:ok, page_life} -> page_life.life
    end
  end

  defp change_modules(resource, action) do
    resource
    |> Ash.Resource.Info.action(action)
    |> Map.fetch!(:changes)
    |> Enum.map(fn %Ash.Resource.Change{change: {module, _opts}} -> module end)
  end
end
