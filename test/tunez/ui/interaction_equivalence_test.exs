defmodule Tunez.UI.InteractionEquivalenceTest do
  use TunezWeb.ConnCase, async: false

  import Phoenix.LiveViewTest, only: [follow_redirect: 3, live: 2]

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
    parity_batch = Tunez.HTMLParity.begin_batch!()

    on_exit(fn -> Tunez.HTMLParity.assert_batch!(parity_batch) end)

    seed!()
    admin = sign_in_admin!()
    %{admin: admin, conn: log_in_user(conn, admin)}
  end

  test "document shell matches title and document-level styling", %{upstream: upstream} do
    Tunez.HTMLParity.assert_document_same!(
      Map.fetch!(upstream, "document_shell"),
      Tunez.HTMLParity.render_blueprint_document()
    )
  end

  test "every catalogue document title matches its upstream screen", %{
    conn: conn,
    upstream: upstream
  } do
    artist_id = Enum.at(@artist_ids, 1)

    for {scenario, request_conn, path} <- [
          {"artist_index_document", build_conn(), "/"},
          {"artist_show_document", conn, "/artists/#{artist_id}"},
          {"artist_new_document", conn, "/artists/new"},
          {"artist_edit_document", conn, "/artists/#{artist_id}/edit"},
          {"album_new_document", conn, "/artists/#{artist_id}/albums/new"},
          {"album_edit_document", conn, "/albums/#{@album_id}/edit"}
        ] do
      blueprint = request_conn |> get(path) |> Map.fetch!(:resp_body)

      Tunez.HTMLParity.assert_document_same!(
        Map.fetch!(upstream, scenario),
        blueprint,
        scenario
      )
    end
  end

  test "artist catalogue matches empty, populated, sorted, and searched states", %{
    conn: conn,
    upstream: upstream
  } do
    assert_parity!(upstream, "artist_index_empty", mount!(build_conn(), "/?q=NO_PARITY_MATCH"))

    assert_parity!(
      upstream,
      "artist_index_invalid_sort",
      mount!(build_conn(), "/?sort_by=definitely_invalid")
    )

    populated = mount!(conn, "/?q=Parity&sort_by=name&limit=1&offset=1")
    assert_parity!(upstream, "artist_index", populated)

    populated
    |> click("[part='avatar_toggle']")
    |> assert_attribute("[part='user_menu']", "aria-expanded", "true")
    |> assert_parity!(upstream, "artist_index_user_menu_open")
    |> click_away("[part='avatar_toggle']")
    |> refute_attribute("[part='user_menu']", "aria-expanded", "true")
    |> click("[part='notifications_toggle']")
    |> assert_attribute("[part='notifications_panel']", "aria-expanded", "true")
    |> assert_parity!(upstream, "artist_index_notifications_open")
    |> click_away("[part='notifications_toggle']")
    |> refute_attribute("[part='notifications_panel']", "aria-expanded", "true")
    |> assert_parity!(upstream, "artist_index")

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

    assert_parity!(
      upstream,
      "artist_show_anonymous",
      mount!(build_conn(), "/artists/#{artist_id}")
    )

    assert_parity!(upstream, "artist_show", view)

    view
    |> click("[part='page_header'][data-kind='responsive'] [part='page_header_toggle']")
    |> assert_attribute(
      "[part='page_header'][data-kind='responsive'] [part='page_header_menu']",
      "aria-expanded",
      "true"
    )
    |> assert_parity!(upstream, "artist_show_responsive_menu_open")
    |> click_away("[part='page_header'][data-kind='responsive'] [part='page_header_toggle']")
    |> refute_attribute(
      "[part='page_header'][data-kind='responsive'] [part='page_header_menu']",
      "aria-expanded",
      "true"
    )
    |> assert_parity!(upstream, "artist_show")

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

    new_mid_edit = mount!(conn, "/artists/new")

    new_mid_edit
    |> change_field("#artist_form_name", "New Artist Draft")
    |> change_field("#artist_form_biography", "New draft biography")
    |> assert_parity!(upstream, "artist_new_mid_edit")

    new_invalid = mount!(conn, "/artists/new")

    new_invalid
    |> change_field("#artist_form_name", "")
    |> change_field("#artist_form_biography", "Draft")
    |> submit_form("#artist_form")
    |> assert_parity!(upstream, "artist_new_error")

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
    |> client_action("#trackSort", "reorder_list", %{"order" => ["1", "0"]})
    |> assert_parity!(upstream, "album_new_after_reorder")
    |> click("tr[data-id='1'] a", "Delete")
    |> assert_parity!(upstream, "album_new_after_remove")

    invalid = mount!(conn, "/artists/#{artist_id}/albums/new")

    invalid
    |> change_field("#album_form_name", "Incomplete Album")
    |> submit_form("#album_form")
    |> assert_parity!(upstream, "album_new_error")

    invalid_track = mount!(conn, "/artists/#{artist_id}/albums/new")

    invalid_track
    |> click("a", "Add Track")
    |> change_field("#album_form_name", "Invalid Track Album")
    |> change_field("#album_form_year_released", "2024")
    |> change_field("#album_form_cover_image_url", "/images/invalid-track.jpg")
    |> change_field("#album_form_tracks_0_name", "Broken Duration")
    |> change_field("#album_form_tracks_0_duration", "bad")
    |> submit_form("#album_form")
    |> assert_parity!(upstream, "album_new_track_error")

    edit_mid = mount!(conn, "/albums/#{@album_id}/edit")

    edit_mid
    |> change_field("#album_form_name", "Edited Album Draft")
    |> change_field("#album_form_year_released", "2023")
    |> change_field("#album_form_cover_image_url", "/images/edited-draft.jpg")
    |> change_field("#album_form_tracks_0_name", "Edited Track Draft")
    |> change_field("#album_form_tracks_0_duration", "5:05")
    |> assert_parity!(upstream, "album_edit_mid_edit")

    edit_invalid = mount!(conn, "/albums/#{@album_id}/edit")

    edit_invalid
    |> change_field("#album_form_name", "")
    |> submit_form("#album_form")
    |> assert_parity!(upstream, "album_edit_error")
  end

  test "successful artist and album edits match the upstream navigation and flash states", %{
    conn: conn,
    upstream: upstream
  } do
    artist_id = Enum.at(@artist_ids, 1)
    conn = Plug.Conn.put_session(conn, "ash_blueprint_session_id", Ash.UUID.generate())

    artist_show =
      conn
      |> mount!("/artists/#{artist_id}/edit")
      |> change_field("#artist_form_name", "Parity M83 Saved")
      |> change_field("#artist_form_biography", "Saved biography\nSaved second line.")
      |> submit_and_follow("#artist_form", conn, "/artists/#{artist_id}")

    assert_parity!(upstream, "artist_edit_success", artist_show)

    album_show =
      conn
      |> mount!("/albums/#{@album_id}/edit")
      |> change_field("#album_form_name", "Saved Album")
      |> change_field("#album_form_year_released", "2025")
      |> change_field("#album_form_cover_image_url", "/images/saved.jpg")
      |> change_field("#album_form_tracks_0_name", "Saved Track")
      |> change_field("#album_form_tracks_0_duration", "6:06")
      |> submit_and_follow("#album_form", conn, "/artists/#{artist_id}")

    assert_parity!(upstream, "album_edit_success", album_show)
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

  defp submit_and_follow(view, selector, conn, path) do
    result =
      view
      |> Phoenix.LiveViewTest.element(selector)
      |> Phoenix.LiveViewTest.render_submit(%{})

    {:ok, next_view, _html} = follow_redirect(result, conn, path)
    next_view
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

  defp click_away(view, selector) do
    [event] =
      view
      |> Phoenix.LiveViewTest.element(selector)
      |> Phoenix.LiveViewTest.render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("phx-click-away")

    Phoenix.LiveViewTest.render_hook(view, event, %{})
    view
  end

  defp assert_attribute(view, selector, name, value) do
    values =
      view
      |> Phoenix.LiveViewTest.element(selector)
      |> Phoenix.LiveViewTest.render()
      |> Floki.parse_fragment!()
      |> Floki.attribute(name)

    assert value in values, "expected #{selector} to have #{name}=#{value}"

    view
  end

  defp refute_attribute(view, selector, name, value) do
    values =
      view
      |> Phoenix.LiveViewTest.element(selector)
      |> Phoenix.LiveViewTest.render()
      |> Floki.parse_fragment!()
      |> Floki.attribute(name)

    refute value in values
    view
  end

  defp client_action(view, selector, using, payload) do
    action =
      view
      |> Phoenix.LiveViewTest.element(selector)
      |> Phoenix.LiveViewTest.render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("data-blueprint-client-actions")
      |> List.first()
      |> Jason.decode!()
      |> Enum.find(&(&1["using"] == using))

    Phoenix.LiveViewTest.render_hook(
      view,
      "ash_blueprint:dispatch",
      Map.merge(%{"action" => action["action"]}, payload)
    )

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
      order: 0,
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
