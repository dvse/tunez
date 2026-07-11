defmodule Tunez.UI.InteractionEquivalenceTest do
  use TunezWeb.ConnCase, async: false

  require Phoenix.LiveViewTest

  @user_id "10000000-0000-4000-8000-000000000001"
  @artist_ids [
    "20000000-0000-4000-8000-000000000001",
    "20000000-0000-4000-8000-000000000002",
    "20000000-0000-4000-8000-000000000003"
  ]
  @album_id "30000000-0000-4000-8000-000000000001"
  @track_id "40000000-0000-4000-8000-000000000001"
  @notification_id "50000000-0000-4000-8000-000000000001"

  setup_all do
    %{upstream: Tunez.HTMLParity.render_upstream_screens!()}
  end

  setup %{conn: conn} do
    seed!()
    admin = sign_in_admin!()
    %{admin: admin, conn: log_in_user(conn, admin)}
  end

  test "artist catalogue matches empty, populated, sorted, and searched states", %{
    conn: conn,
    upstream: upstream
  } do
    assert_parity!(upstream, "artist_index_empty", mount!(build_conn(), "/?q=NO_PARITY_MATCH"))

    populated = mount!(conn, "/?q=Parity&sort_by=name&limit=1&offset=1")
    assert_parity!(upstream, "artist_index", populated)

    sorted = mount!(conn, "/?q=Parity&sort_by=name")

    sorted
    |> change_form("[data-role='artist-sort']", "sort_by", "-album_count")
    |> assert_parity!(upstream, "artist_index_sorted")

    searched = mount!(conn, "/?sort_by=name")

    searched
    |> change_field("#search-text", "Omega")
    |> submit_form("[data-role='artist-search']")
    |> assert_parity!(upstream, "artist_index_searched")
  end

  test "artist details match followed, unfollowed, and refollowed states", %{
    conn: conn,
    upstream: upstream
  } do
    artist_id = Enum.at(@artist_ids, 1)
    view = mount!(conn, "/artists/#{artist_id}")

    assert_parity!(upstream, "artist_show", view)

    view
    |> click("[part='follow_toggle']")
    |> assert_parity!(upstream, "artist_show_unfollowed")
    |> click("[part='follow_toggle']")
    |> assert_parity!(upstream, "artist_show_refollowed")
  end

  test "artist forms match new, edit, mid-edit, and validation-error states", %{
    conn: conn,
    upstream: upstream
  } do
    artist_id = Enum.at(@artist_ids, 1)

    assert_parity!(upstream, "artist_new", mount!(conn, "/artists/new"))
    assert_parity!(upstream, "artist_edit", mount!(conn, "/artists/#{artist_id}/edit"))

    mid_edit = mount!(conn, "/artists/#{artist_id}/edit")

    mid_edit
    |> change_field("#artist_form_name", "Parity M83 Draft")
    |> change_field("#artist_form_biography", "Draft biography\nSecond draft line.")
    |> assert_parity!(upstream, "artist_edit_mid_edit")

    invalid = mount!(conn, "/artists/#{artist_id}/edit")

    invalid
    |> change_field("#artist_form_name", "")
    |> change_field("#artist_form_biography", "Draft biography")
    |> submit_form("#artist_form")
    |> assert_parity!(upstream, "artist_edit_error")
  end

  test "album forms match new, edit, mid-edit, row-removal, and error states", %{
    conn: conn,
    upstream: upstream
  } do
    artist_id = Enum.at(@artist_ids, 1)

    assert_parity!(
      upstream,
      "album_new",
      mount!(conn, "/artists/#{artist_id}/albums/new")
    )

    assert_parity!(upstream, "album_edit", mount!(conn, "/albums/#{@album_id}/edit"))

    mid_edit = mount!(conn, "/artists/#{artist_id}/albums/new")

    mid_edit
    |> click("a", "Add Track")
    |> click("a", "Add Track")
    |> change_field("#album_form_name", "Draft Album")
    |> change_field("#album_form_year_released", "2024")
    |> change_field("#album_form_cover_image_url", "/images/draft.jpg")
    |> change_field("#album_form_tracks_0_name", "Draft One")
    |> change_field("#album_form_tracks_0_duration", "2:22")
    |> change_field("#album_form_tracks_1_name", "Draft Two")
    |> change_field("#album_form_tracks_1_duration", "3:33")
    |> assert_parity!(upstream, "album_new_mid_edit")
    |> click("tr[data-id='1'] a", "Delete")
    |> assert_parity!(upstream, "album_new_after_remove")

    invalid = mount!(conn, "/artists/#{artist_id}/albums/new")

    invalid
    |> change_field("#album_form_name", "Incomplete Album")
    |> submit_form("#album_form")
    |> assert_parity!(upstream, "album_new_error")
  end

  defp assert_parity!(view, upstream, scenario)
       when is_map(upstream) and is_binary(scenario) do
    assert_parity!(upstream, scenario, view)
    view
  end

  defp assert_parity!(upstream, scenario, view)
       when is_map(upstream) and is_binary(scenario) do
    Tunez.HTMLParity.assert_app_same!(
      Map.fetch!(upstream, scenario),
      Phoenix.LiveViewTest.render(view),
      scenario
    )
  end

  defp mount!(conn, path) do
    {:ok, view, _html} = Phoenix.LiveViewTest.live(conn, path)
    view
  end

  defp change_field(view, selector, value) do
    element = Phoenix.LiveViewTest.element(view, selector)

    [name] =
      element
      |> Phoenix.LiveViewTest.render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("name")

    Phoenix.LiveViewTest.render_change(element, %{"_target" => [name], name => value})
    view
  end

  defp change_form(view, selector, name, value) do
    view
    |> Phoenix.LiveViewTest.element(selector)
    |> Phoenix.LiveViewTest.render_change(%{"_target" => [name], name => value})

    view
  end

  defp submit_form(view, selector) do
    view
    |> Phoenix.LiveViewTest.element(selector)
    |> Phoenix.LiveViewTest.render_submit(%{})

    view
  end

  defp click(view, selector, text \\ nil) do
    element =
      if text do
        Phoenix.LiveViewTest.element(view, selector, text)
      else
        Phoenix.LiveViewTest.element(view, selector)
      end

    Phoenix.LiveViewTest.render_click(element)
    view
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
