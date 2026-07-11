defmodule Tunez.UI.HTMLParityTest do
  use TunezWeb.ConnCase, async: false

  require Phoenix.LiveViewTest

  alias Tunez.HTMLParity

  @user_id "10000000-0000-4000-8000-000000000001"
  @artist_ids [
    "20000000-0000-4000-8000-000000000001",
    "20000000-0000-4000-8000-000000000002",
    "20000000-0000-4000-8000-000000000003"
  ]
  @album_id "30000000-0000-4000-8000-000000000001"
  @track_id "40000000-0000-4000-8000-000000000001"
  @notification_id "50000000-0000-4000-8000-000000000001"

  @covered_routed_screens MapSet.new([
                            Tunez.UI.AlbumFormPage,
                            Tunez.UI.ArtistFormPage,
                            Tunez.UI.ArtistIndexPage,
                            Tunez.UI.ArtistShowPage
                          ])

  setup_all do
    {:ok, upstream: HTMLParity.render_upstream_screens!()}
  end

  setup do
    {:ok, admin: seed!()}
  end

  test "every routed screen is covered and only the proved catalogue reads are manual" do
    routed_screens =
      Tunez.UI
      |> Ash.Domain.Info.resources()
      |> Enum.filter(fn resource ->
        Code.ensure_loaded!(resource)
        function_exported?(resource, :__ash_blueprint_route__, 0)
      end)
      |> MapSet.new()

    assert routed_screens == @covered_routed_screens

    manual_relationships =
      for resource <- Ash.Domain.Info.resources(Tunez.UI),
          relationship <- Ash.Resource.Info.relationships(resource),
          Map.get(relationship, :manual) not in [nil, false],
          do: {resource, relationship.name}

    assert MapSet.new(manual_relationships) ==
             MapSet.new([
               {Tunez.UI.ArtistIndexPage, :artists},
               {Tunez.UI.ArtistIndexPage, :next_artist}
             ])
  end

  test "actual chapter-10 and AshBlueprint HTML and computed styles match on every screen", %{
    upstream: upstream,
    admin: admin
  } do
    artist_id = Enum.at(@artist_ids, 1)

    scenarios = [
      {"artist_index_empty", build_conn(), "/?q=NO_PARITY_MATCH"},
      {"artist_index", log_in_user(build_conn(), admin),
       "/?q=Parity&sort_by=name&limit=1&offset=1"},
      {"artist_show", log_in_user(build_conn(), admin), "/artists/#{artist_id}"},
      {"artist_new", log_in_user(build_conn(), admin), "/artists/new"},
      {"artist_edit", log_in_user(build_conn(), admin), "/artists/#{artist_id}/edit"},
      {"album_new", log_in_user(build_conn(), admin), "/artists/#{artist_id}/albums/new"},
      {"album_edit", log_in_user(build_conn(), admin), "/albums/#{@album_id}/edit"}
    ]

    failures =
      Enum.flat_map(scenarios, fn {name, conn, path} ->
        try do
          {:ok, view, _html} = Phoenix.LiveViewTest.live(conn, path)

          HTMLParity.assert_app_same!(
            Map.fetch!(upstream, name),
            Phoenix.LiveViewTest.render(view),
            name
          )

          []
        rescue
          error in [ExUnit.AssertionError] -> ["#{name}: #{Exception.message(error)}"]
        end
      end)

    assert failures == [], Enum.join(failures, "\n\n")
  end

  defp seed! do
    now = ~U[2026-07-10 12:00:00Z]

    Tunez.Accounts.User
    |> Ash.Changeset.for_create(
      :register_with_password,
      %{
        email: "admin@parity.test",
        password: "parity-password",
        password_confirmation: "parity-password"
      },
      authorize?: false
    )
    |> Ash.Changeset.force_change_attribute(:id, @user_id)
    |> Ash.create!(authorize?: false)
    |> Tunez.Accounts.set_user_role!(:admin, authorize?: false)

    ["Parity Alpha", "Parity M83", "Parity Omega"]
    |> Enum.zip(@artist_ids)
    |> Enum.each(fn {name, id} ->
      Ash.Seed.seed!(Tunez.Music.Artist, %{
        id: id,
        name: name,
        biography: "French electronic music project.\nSecond line.",
        previous_names: if(name == "Parity M83", do: ["M-83"], else: []),
        inserted_at: now,
        updated_at: now
      })
    end)

    Ash.Seed.seed!(Tunez.Music.Album, %{
      id: @album_id,
      artist_id: Enum.at(@artist_ids, 1),
      name: "Hurry Up, We're Dreaming",
      year_released: 2011,
      cover_image_url: "https://example.test/hurry-up.jpg",
      inserted_at: now,
      updated_at: now
    })

    Ash.Seed.seed!(Tunez.Music.Track, %{
      id: @track_id,
      album_id: @album_id,
      order: 9,
      name: "Midnight City",
      duration_seconds: 243,
      inserted_at: now,
      updated_at: now
    })

    Ash.Seed.seed!(Tunez.Music.ArtistFollower, %{
      artist_id: Enum.at(@artist_ids, 1),
      follower_id: @user_id
    })

    Ash.Seed.seed!(Tunez.Accounts.Notification, %{
      id: @notification_id,
      user_id: @user_id,
      album_id: @album_id,
      inserted_at: now
    })

    Tunez.Accounts.User
    |> Ash.Query.for_read(
      :sign_in_with_password,
      %{email: "admin@parity.test", password: "parity-password"},
      authorize?: false
    )
    |> Ash.read_one!(authorize?: false)
  end
end
