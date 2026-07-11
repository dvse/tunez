defmodule Tunez.UI.Chapter10FunctionalityTest do
  use TunezWeb.ConnCase, async: false

  alias Tunez.Music

  describe "artist catalogue and details" do
    test "lists artists and their album summaries", %{conn: conn} do
      artist = generate(artist())

      conn
      |> visit(~p"/")
      |> assert_has("#artist-#{artist.id}")
      |> refute_has("span", text: "0 albums")

      generate(album(artist_id: artist.id))

      conn
      |> visit(~p"/")
      |> assert_has(link(~p"/artists/#{artist.id}"))
      |> assert_has("span", text: "1 album")
    end

    test "shows artist, album, and track details", %{conn: conn} do
      album = generate(album(track_count: 2))

      conn
      |> visit(~p"/artists/#{album.artist_id}")
      |> assert_has("h1")
      |> within("#album-#{album.id}", fn session ->
        session
        |> assert_has("h2", text: album.name)
        |> assert_has("td", text: Enum.at(album.tracks, 0).name)
        |> assert_has("td", text: Enum.at(album.tracks, 1).name)
      end)
    end

    test "only authorized actors see catalogue management links", %{conn: conn} do
      album = generate(album())

      conn
      |> visit(~p"/artists/#{album.artist_id}")
      |> refute_has(link(~p"/artists/#{album.artist_id}/edit"))
      |> refute_has(link(~p"/albums/#{album.id}/edit"))
      |> refute_has("a", text: "Delete Artist")
      |> refute_has("#album-#{album.id} a", text: "Delete")

      conn
      |> insert_and_authenticate_user(:admin)
      |> visit(~p"/artists/#{album.artist_id}")
      |> assert_has(link(~p"/artists/#{album.artist_id}/edit"))
      |> assert_has(link(~p"/albums/#{album.id}/edit"))
      |> assert_has("a", text: "Delete Artist")
      |> assert_has("#album-#{album.id} a", text: "Delete")
    end

    test "authenticated users can follow and unfollow an artist", %{conn: conn} do
      artist = generate(artist())

      session =
        conn
        |> insert_and_authenticate_user(:user)
        |> visit(~p"/artists/#{artist.id}")
        |> click_selector("[part=follow_toggle]")

      assert_has(session, ~s([part="follow_toggle_icon"][aria-selected="true"]))

      assert Music.get_artist_by_id!(artist.id, load: [:follower_count]).follower_count == 1

      session
      |> click_selector("[part=follow_toggle]")
      |> assert_has(~s|[part="follow_toggle_icon"]:not([aria-selected="true"])|)

      assert Music.get_artist_by_id!(artist.id, load: [:follower_count]).follower_count == 0
    end

    test "admin can delete an album and artist", %{conn: conn} do
      album = generate(album())

      conn
      |> insert_and_authenticate_user(:admin)
      |> visit(~p"/artists/#{album.artist_id}")
      |> click_link("#album-#{album.id} a", "Delete")
      |> assert_has(~s([part="flash_message"][data-kind="info"]),
        text: "Album deleted successfully"
      )

      assert {:error, _error} = Music.get_album_by_id(album.id)

      conn
      |> insert_and_authenticate_user(:admin)
      |> visit(~p"/artists/#{album.artist_id}")
      |> click_link("Delete Artist")
      |> assert_has(~s([part="flash_message"][data-kind="info"]),
        text: "Artist deleted successfully"
      )

      assert {:error, _error} = Music.get_artist_by_id(album.artist_id)
    end
  end

  describe "artist forms" do
    test "ordinary users cannot mount artist forms", %{conn: conn} do
      artist = generate(artist())
      conn = insert_and_authenticate_user(conn, :user)

      assert_raise Ash.Error.Forbidden, fn -> visit(conn, ~p"/artists/new") end
      assert_raise Ash.Error.Forbidden, fn -> visit(conn, ~p"/artists/#{artist.id}/edit") end
    end

    test "admin creates and updates an artist", %{conn: conn} do
      conn
      |> insert_and_authenticate_user(:admin)
      |> visit(~p"/artists/new")
      |> change_field("#artist_form_name", "Temperance")
      |> change_field("#artist_form_biography", "Electronic music")
      |> assert_field_value("#artist_form_name", "Temperance")
      |> assert_field_value("#artist_form_biography", "Electronic music")
      |> click_button("Save")
      |> assert_has(~s([part="flash_message"][data-kind="info"]),
        text: "Artist saved successfully"
      )
      |> assert_has("h1", text: "Temperance")

      artist = get_by_name!(Tunez.Music.Artist, "Temperance")
      assert artist.biography == "Electronic music"

      conn
      |> insert_and_authenticate_user(:admin)
      |> visit(~p"/artists/#{artist.id}/edit")
      |> change_field("#artist_form_name", "New Temperance")
      |> change_field("#artist_form_biography", "New electronic music")
      |> assert_field_value("#artist_form_name", "New Temperance")
      |> assert_field_value("#artist_form_biography", "New electronic music")
      |> click_button("Save")
      |> assert_has(~s([part="flash_message"][data-kind="info"]),
        text: "Artist saved successfully"
      )
      |> assert_has("h1", text: "New Temperance")

      updated_artist = Music.get_artist_by_id!(artist.id)
      assert updated_artist.name == "New Temperance"
      assert updated_artist.biography == "New electronic music"
    end

    test "invalid artist data is rejected without changing domain state", %{conn: conn} do
      artist = generate(artist(name: "Old Name"))

      # FULL upstream parity: the failed save flashes AND shows the field
      # error text inline; the bound control lights up (aria-invalid +
      # message); the domain and the location stay put.
      conn
      |> insert_and_authenticate_user(:admin)
      |> visit(~p"/artists/#{artist.id}/edit")
      |> change_field("#artist_form_name", "")
      |> click_button("Save")
      |> assert_has(~s(#artist_form_name[aria-invalid="true"]))
      |> assert_has(~s(#artist_form_name[data-blueprint-error]))
      |> assert_has(~s([part="field_error"]), text: "is required")
      |> assert_has(~s([part="flash_message"][data-kind="error"]),
        text: "Could not save artist data"
      )
      |> assert_path("/artists/#{artist.id}/edit")

      assert Music.get_artist_by_id!(artist.id).name == "Old Name"
    end
  end

  describe "album forms" do
    test "ordinary users cannot mount album forms", %{conn: conn} do
      album = generate(album())
      conn = insert_and_authenticate_user(conn, :user)

      assert_raise Ash.Error.Forbidden, fn ->
        visit(conn, ~p"/artists/#{album.artist_id}/albums/new")
      end

      assert_raise Ash.Error.Forbidden, fn -> visit(conn, ~p"/albums/#{album.id}/edit") end
    end

    test "admin creates an album with editable embedded track rows", %{conn: conn} do
      artist = generate(artist())

      conn
      |> insert_and_authenticate_user(:admin)
      |> visit(~p"/artists/#{artist.id}/albums/new")
      |> change_field("#album_form_name", "Sample With Tracks")
      |> change_field("#album_form_year_released", "2021")
      |> change_field("#album_form_cover_image_url", "/images/sample.jpg")
      |> assert_field_value("#album_form_name", "Sample With Tracks")
      |> assert_field_value("#album_form_year_released", "2021")
      |> assert_field_value("#album_form_cover_image_url", "/images/sample.jpg")
      |> click_link("Add Track")
      |> assert_field_value("#album_form_name", "Sample With Tracks")
      |> assert_field_value("#album_form_year_released", "2021")
      |> assert_field_value("#album_form_cover_image_url", "/images/sample.jpg")
      |> assert_has("tr[data-id]", count: 1)
      |> change_field("#album_form_tracks_0_name", "First Track")
      |> change_field("#album_form_tracks_0_duration", "2:22")
      |> click_link("Add Track")
      |> assert_field_value("#album_form_tracks_0_name", "First Track")
      |> assert_field_value("#album_form_tracks_0_duration", "2:22")
      |> assert_has("tr[data-id]", count: 2)
      |> change_field("#album_form_tracks_1_name", "Second Track")
      |> change_field("#album_form_tracks_1_duration", "3:33")
      |> click_link("Add Track")
      |> assert_field_value("#album_form_tracks_0_name", "First Track")
      |> assert_field_value("#album_form_tracks_0_duration", "2:22")
      |> assert_field_value("#album_form_tracks_1_name", "Second Track")
      |> assert_field_value("#album_form_tracks_1_duration", "3:33")
      |> assert_has("tr[data-id]", count: 3)
      |> change_field("#album_form_tracks_2_name", "Third Track")
      |> click_link("tr[data-id='2'] a", "Delete")
      |> assert_has("tr[data-id]", count: 2)
      |> assert_field_value("#album_form_tracks_0_name", "First Track")
      |> assert_field_value("#album_form_tracks_1_name", "Second Track")
      |> click_button("Save")
      |> assert_has(~s([part="flash_message"][data-kind="info"]),
        text: "Album saved successfully"
      )
      |> assert_has("h2", text: "Sample With Tracks")

      album = get_by_name!(Tunez.Music.Album, "Sample With Tracks", load: [:tracks])
      assert album.artist_id == artist.id
      assert album.year_released == 2021
      assert album.cover_image_url == "/images/sample.jpg"

      assert Enum.map(album.tracks, &{&1.name, &1.duration}) == [
               {"First Track", "2:22"},
               {"Second Track", "3:33"}
             ]
    end

    test "admin updates an album and invalid changes leave it unchanged", %{conn: conn} do
      album =
        generate(
          album(
            name: "Old Name",
            year_released: 1999,
            cover_image_url: "/images/old.jpg",
            track_count: 2
          )
        )

      [kept_track, removed_track] = album.tracks

      conn
      |> insert_and_authenticate_user(:admin)
      |> visit(~p"/albums/#{album.id}/edit")
      |> change_field("#album_form_name", "New Name")
      |> change_field("#album_form_year_released", "2024")
      |> change_field("#album_form_cover_image_url", "/images/updated.jpg")
      |> change_field("#album_form_tracks_0_name", "Edited Existing Track")
      |> change_field("#album_form_tracks_0_duration", "4:44")
      |> click_link("Add Track")
      |> assert_field_value("#album_form_name", "New Name")
      |> assert_field_value("#album_form_year_released", "2024")
      |> assert_field_value("#album_form_cover_image_url", "/images/updated.jpg")
      |> assert_field_value("#album_form_tracks_0_name", "Edited Existing Track")
      |> assert_field_value("#album_form_tracks_0_duration", "4:44")
      |> assert_has("tr[data-id]", count: 3)
      |> change_field("#album_form_tracks_2_name", "Added Track")
      |> change_field("#album_form_tracks_2_duration", "5:55")
      |> click_link("tr[data-id='1'] a", "Delete")
      |> assert_has("tr[data-id]", count: 2)
      |> assert_field_value("#album_form_tracks_0_name", "Edited Existing Track")
      |> assert_field_value("#album_form_tracks_1_name", "Added Track")
      |> assert_field_value("#album_form_tracks_1_duration", "5:55")
      |> click_button("Save")
      |> assert_has(~s([part="flash_message"][data-kind="info"]),
        text: "Album saved successfully"
      )
      |> assert_has("h2", text: "New Name")

      updated_album = Music.get_album_by_id!(album.id, load: [:tracks])
      assert updated_album.name == "New Name"
      assert updated_album.year_released == 2024
      assert updated_album.cover_image_url == "/images/updated.jpg"

      assert Enum.map(updated_album.tracks, &{&1.name, &1.duration}) == [
               {"Edited Existing Track", "4:44"},
               {"Added Track", "5:55"}
             ]

      assert hd(updated_album.tracks).id == kept_track.id
      refute Enum.at(updated_album.tracks, 1).id in [kept_track.id, removed_track.id]
      refute Enum.any?(updated_album.tracks, &(&1.id == removed_track.id))

      # FULL upstream parity: the failed save flashes AND shows the field
      # error text inline; the bound control lights up; the domain and the
      # location stay put.
      conn
      |> insert_and_authenticate_user(:admin)
      |> visit(~p"/albums/#{album.id}/edit")
      |> change_field("#album_form_name", "")
      |> click_button("Save")
      |> assert_has(~s(#album_form_name[aria-invalid="true"]))
      |> assert_has(~s(#album_form_name[data-blueprint-error]))
      |> assert_has(~s([part="field_error"]), text: "is required")
      |> assert_has(~s([part="flash_message"][data-kind="error"]),
        text: "Could not save album data"
      )
      |> assert_path("/albums/#{album.id}/edit")

      assert Music.get_album_by_id!(album.id).name == "New Name"
    end
  end

  describe "notifications" do
    test "the signed-in user menu is Ash state and toggles from the avatar", %{conn: conn} do
      user = generate(user(role: :user))

      session =
        conn
        |> log_in_user(user)
        |> visit(~p"/")
        |> assert_has("[part=user_menu]")
        |> click_selector("[part=avatar_toggle]")

      assert Enum.any?(Ash.read!(Tunez.UI.Navigation, authorize?: false), fn navigation ->
               navigation.email == to_string(user.email) and navigation.menu_open?
             end)

      assert_has(session, "[part=user_menu][aria-expanded=true]")

      session
      |> click_selector("[part=avatar_toggle]")
      |> assert_has("[part=user_menu]")
    end

    test "notification bell opens and dismisses a domain notification", %{conn: conn} do
      user = generate(user(role: :user))
      album = generate(album())
      notification = generate(notification(user_id: user.id, album_id: album.id))

      session =
        conn
        |> log_in_user(user)
        |> visit(~p"/")
        |> assert_has("[part=notifications_badge]")
        |> click_selector("[part=notifications_toggle]")

      assert Enum.any?(Ash.read!(Tunez.UI.NotificationsPage, authorize?: false), & &1.open?)
      assert_has(session, "[part=notifications_panel][aria-expanded=true]")

      session
      |> click_selector("[part=notification_item_link]")
      |> refute_has("[part=notifications_badge]")

      assert {:error, _error} =
               Tunez.Accounts.get_notification_by_id(notification.id, actor: user)
    end
  end

  defp change_field(session, selector, value) do
    unwrap(session, fn view ->
      element = Phoenix.LiveViewTest.element(view, selector)

      [name] =
        element
        |> Phoenix.LiveViewTest.render()
        |> Floki.parse_fragment!()
        |> Floki.attribute("name")

      Phoenix.LiveViewTest.render_change(element, %{
        "_target" => [name],
        name => value
      })
    end)
  end

  defp assert_field_value(session, selector, expected) do
    unwrap(session, fn view ->
      html =
        view
        |> Phoenix.LiveViewTest.element(selector)
        |> Phoenix.LiveViewTest.render()

      nodes = Floki.parse_fragment!(html)

      actual =
        case Floki.attribute(nodes, "value") do
          [value] -> value
          [] -> Floki.text(nodes)
        end

      assert actual == expected
      html
    end)
  end

  defp click_selector(session, selector) do
    unwrap(session, fn view ->
      view
      |> Phoenix.LiveViewTest.element(selector)
      |> Phoenix.LiveViewTest.render_click()
    end)
  end
end
