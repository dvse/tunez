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

    screens =
      %{
        "document_shell" => render_component(&TunezWeb.Layouts.root/1, inner_content: ""),
        "artist_index_document" => document(build_conn(), "/"),
        "artist_show_document" => document(log_in(build_conn(), admin), "/artists/#{artist_id}"),
        "artist_new_document" => document(log_in(build_conn(), admin), "/artists/new"),
        "artist_edit_document" =>
          document(log_in(build_conn(), admin), "/artists/#{artist_id}/edit"),
        "album_new_document" =>
          document(log_in(build_conn(), admin), "/artists/#{artist_id}/albums/new"),
        "album_edit_document" =>
          document(log_in(build_conn(), admin), "/albums/#{@album_id}/edit"),
        "artist_index_empty" => render(build_conn(), "/?q=NO_PARITY_MATCH"),
        "artist_index_invalid_sort" => render(build_conn(), "/?sort_by=definitely_invalid"),
        "artist_index" =>
          render(log_in(build_conn(), admin), "/?q=Parity&sort_by=name&limit=1&offset=1"),
        "artist_show" => render(log_in(build_conn(), admin), "/artists/#{artist_id}"),
        "artist_show_anonymous" => render(build_conn(), "/artists/#{artist_id}"),
        "artist_new" => render(log_in(build_conn(), admin), "/artists/new"),
        "artist_edit" => render(log_in(build_conn(), admin), "/artists/#{artist_id}/edit"),
        "album_new" => render(log_in(build_conn(), admin), "/artists/#{artist_id}/albums/new"),
        "album_edit" => render(log_in(build_conn(), admin), "/albums/#{@album_id}/edit")
      }
      |> Map.merge(index_interaction_states(admin))
      |> Map.merge(show_interaction_states(admin, artist_id))
      |> Map.merge(artist_form_interaction_states(admin, artist_id))
      |> Map.merge(album_form_interaction_states(admin, artist_id))
      |> Map.merge(success_interaction_states(admin, artist_id))

    IO.puts("ASH_BLUEPRINT_UPSTREAM_ORACLE=" <> Base.encode64(:erlang.term_to_binary(screens)))
  end

  defp render(conn, path) do
    {:ok, view, _html} = live(conn, path)
    Phoenix.LiveViewTest.render(view)
  end

  defp document(conn, path), do: conn |> get(path) |> Map.fetch!(:resp_body)

  defp mount(admin, path) do
    {:ok, view, _html} = live(log_in(build_conn(), admin), path)
    view
  end

  defp index_interaction_states(admin) do
    menu_state = mount(admin, "/?q=Parity&sort_by=name&limit=1&offset=1")
    menu_html = Phoenix.LiveViewTest.render(menu_state)
    sorted = mount(admin, "/?q=Parity&sort_by=name")
    render_change(sorted, "change-sort", %{"sort_by" => "-album_count"})

    searched = mount(admin, "/?sort_by=name")
    render_submit(searched, "search", %{"query" => "Omega"})

    %{
      "artist_index_user_menu_open" => show_id(menu_html, "user-menu"),
      "artist_index_notifications_open" => show_id(menu_html, "notifications"),
      "artist_index_sorted" => Phoenix.LiveViewTest.render(sorted),
      "artist_index_searched" => Phoenix.LiveViewTest.render(searched)
    }
  end

  defp show_interaction_states(admin, artist_id) do
    view = mount(admin, "/artists/#{artist_id}")
    responsive_menu_open = view |> Phoenix.LiveViewTest.render() |> show_first_dropdown()
    render_click(view, "unfollow", %{})
    unfollowed = Phoenix.LiveViewTest.render(view)
    render_click(view, "follow", %{})

    %{
      "artist_show_responsive_menu_open" => responsive_menu_open,
      "artist_show_unfollowed" => unfollowed,
      "artist_show_refollowed" => Phoenix.LiveViewTest.render(view)
    }
  end

  defp artist_form_interaction_states(admin, artist_id) do
    new_mid_edit = mount(admin, "/artists/new")

    render_change(new_mid_edit, "validate", %{
      "form" => %{"name" => "New Artist Draft", "biography" => "New draft biography"}
    })

    new_invalid = mount(admin, "/artists/new")
    render_submit(new_invalid, "save", %{"form" => %{"name" => "", "biography" => "Draft"}})

    mid_edit = mount(admin, "/artists/#{artist_id}/edit")

    render_change(mid_edit, "validate", %{
      "form" => %{
        "name" => "Parity M83 Draft",
        "biography" => "Draft biography\nSecond draft line."
      }
    })

    invalid = mount(admin, "/artists/#{artist_id}/edit")

    render_submit(invalid, "save", %{
      "form" => %{"name" => "", "biography" => "Draft biography"}
    })

    %{
      "artist_new_mid_edit" => Phoenix.LiveViewTest.render(new_mid_edit),
      "artist_new_error" => Phoenix.LiveViewTest.render(new_invalid),
      "artist_edit_mid_edit" => Phoenix.LiveViewTest.render(mid_edit),
      "artist_edit_error" => Phoenix.LiveViewTest.render(invalid)
    }
  end

  defp album_form_interaction_states(admin, artist_id) do
    mid_edit = mount(admin, "/artists/#{artist_id}/albums/new")
    render_click(mid_edit, "add-track", %{})
    render_click(mid_edit, "add-track", %{})

    render_change(mid_edit, "validate", %{
      "form" => %{
        "name" => "Draft Album",
        "year_released" => "2024",
        "cover_image_url" => "/images/draft.jpg",
        "tracks" => %{
          "0" => %{"name" => "Draft One", "duration" => "2:22"},
          "1" => %{"name" => "Draft Two", "duration" => "3:33"}
        }
      }
    })

    with_removed_track = Phoenix.LiveViewTest.render(mid_edit)
    render_hook(mid_edit, "reorder-tracks", %{"order" => ["1", "0"]})
    reordered = Phoenix.LiveViewTest.render(mid_edit)
    render_click(mid_edit, "remove-track", %{"path" => "form[tracks][1]"})

    invalid = mount(admin, "/artists/#{artist_id}/albums/new")

    render_submit(invalid, "save", %{
      "form" => %{
        "name" => "Incomplete Album",
        "year_released" => "",
        "cover_image_url" => ""
      }
    })

    edit_mid = mount(admin, "/albums/#{@album_id}/edit")

    render_change(edit_mid, "validate", %{
      "form" => %{
        "name" => "Edited Album Draft",
        "year_released" => "2023",
        "cover_image_url" => "/images/edited-draft.jpg",
        "tracks" => %{"0" => %{"name" => "Edited Track Draft", "duration" => "5:05"}}
      }
    })

    edit_invalid = mount(admin, "/albums/#{@album_id}/edit")

    render_submit(edit_invalid, "save", %{
      "form" => %{
        "name" => "",
        "year_released" => "2011",
        "cover_image_url" => "https://example.test/hurry-up.jpg",
        "tracks" => %{"0" => %{"name" => "Midnight City", "duration" => "4:03"}}
      }
    })

    invalid_track = mount(admin, "/artists/#{artist_id}/albums/new")
    render_click(invalid_track, "add-track", %{})

    render_submit(invalid_track, "save", %{
      "form" => %{
        "name" => "Invalid Track Album",
        "year_released" => "2024",
        "cover_image_url" => "/images/invalid-track.jpg",
        "tracks" => %{"0" => %{"name" => "Broken Duration", "duration" => "bad"}}
      }
    })

    %{
      "album_new_mid_edit" => with_removed_track,
      "album_new_after_reorder" => reordered,
      "album_new_after_remove" => Phoenix.LiveViewTest.render(mid_edit),
      "album_new_error" => Phoenix.LiveViewTest.render(invalid),
      "album_new_track_error" => Phoenix.LiveViewTest.render(invalid_track),
      "album_edit_mid_edit" => Phoenix.LiveViewTest.render(edit_mid),
      "album_edit_error" => Phoenix.LiveViewTest.render(edit_invalid)
    }
  end

  defp success_interaction_states(admin, artist_id) do
    session_id = Ash.UUID.generate()
    conn = log_in(build_conn(), admin, session_id)
    {:ok, artist_edit, _html} = live(conn, "/artists/#{artist_id}/edit")

    artist_result =
      render_submit(artist_edit, "save", %{
        "form" => %{
          "name" => "Parity M83 Saved",
          "biography" => "Saved biography\nSaved second line."
        }
      })

    {:ok, artist_show, _html} =
      follow_redirect(
        artist_result,
        conn,
        "/artists/#{artist_id}"
      )

    {:ok, album_edit, _html} = live(conn, "/albums/#{@album_id}/edit")

    album_result =
      render_submit(album_edit, "save", %{
        "form" => %{
          "name" => "Saved Album",
          "year_released" => "2025",
          "cover_image_url" => "/images/saved.jpg",
          "tracks" => %{"0" => %{"name" => "Saved Track", "duration" => "6:06"}}
        }
      })

    {:ok, album_show, _html} =
      follow_redirect(
        album_result,
        conn,
        "/artists/#{artist_id}"
      )

    %{
      "artist_edit_success" => Phoenix.LiveViewTest.render(artist_show),
      "album_edit_success" => Phoenix.LiveViewTest.render(album_show)
    }
  end

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  defp log_in(conn, user, session_id) do
    conn
    |> log_in(user)
    |> Plug.Conn.put_session("ash_blueprint_session_id", session_id)
  end

  defp show_first_dropdown(html) do
    [_, id] = Regex.run(~r/<header.*?<div id="(dropdown_[^"]+)"/s, html)
    show_id(html, id)
  end

  defp show_id(html, id) do
    Regex.replace(
      ~r/(<[^>]+id="#{Regex.escape(id)}"[^>]+class=")([^"]*)"/,
      html,
      fn _match, prefix, classes ->
        visible_classes =
          classes
          |> String.split()
          |> Enum.reject(&(&1 in ["hidden", "max-sm:hidden"]))
          |> Enum.join(" ")

        prefix <> visible_classes <> "\""
      end,
      global: false
    )
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
