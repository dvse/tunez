ExUnit.start(autorun: false)

defmodule Tunez.UpstreamOracle do
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint TunezWeb.Endpoint

  @user_id "10000000-0000-4000-8000-000000000001"
  @artist_ids [
    "20000000-0000-4000-8000-000000000001",
    "20000000-0000-4000-8000-000000000002",
    "20000000-0000-4000-8000-000000000003"
  ]
  @album_id "30000000-0000-4000-8000-000000000001"
  @track_id "40000000-0000-4000-8000-000000000001"
  @notification_id "50000000-0000-4000-8000-000000000001"

  def run do
    Ecto.Adapters.SQL.Sandbox.checkout(Tunez.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Tunez.Repo, {:shared, self()})
    seed!()

    admin = sign_in_admin!()
    artist_id = Enum.at(@artist_ids, 1)

    screens = %{
      "artist_index_empty" => render(build_conn(), "/?q=NO_PARITY_MATCH"),
      "artist_index" =>
        render(log_in(build_conn(), admin), "/?q=Parity&sort_by=name&limit=1&offset=1"),
      "artist_show" => render(log_in(build_conn(), admin), "/artists/#{artist_id}"),
      "artist_new" => render(log_in(build_conn(), admin), "/artists/new"),
      "artist_edit" => render(log_in(build_conn(), admin), "/artists/#{artist_id}/edit"),
      "album_new" => render(log_in(build_conn(), admin), "/artists/#{artist_id}/albums/new"),
      "album_edit" => render(log_in(build_conn(), admin), "/albums/#{@album_id}/edit")
    }

    IO.puts("ASH_BLUEPRINT_UPSTREAM_ORACLE=" <> Base.encode64(:erlang.term_to_binary(screens)))
  end

  defp render(conn, path) do
    {:ok, view, _html} = live(conn, path)
    Phoenix.LiveViewTest.render(view)
  end

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
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
  end

  defp sign_in_admin! do
    Tunez.Accounts.User
    |> Ash.Query.for_read(
      :sign_in_with_password,
      %{email: "admin@parity.test", password: "parity-password"},
      authorize?: false
    )
    |> Ash.read_one!(authorize?: false)
  end
end

defmodule Tunez.UpstreamOracleTest do
  use ExUnit.Case, async: false

  test "renders the actual chapter 10 screens" do
    Tunez.UpstreamOracle.run()
  end
end

case ExUnit.run() do
  %{failures: 0} -> :ok
  _results -> System.halt(1)
end
