defmodule Tunez.UI.LiveFunctionalityTest do
  use TunezWeb.ConnCase, async: false

  describe "artist catalogue interactions" do
    test "results can be paged through", %{conn: conn} do
      generate_many(artist(), 3)

      conn
      |> visit(~p"/?limit=1")
      |> assert_has("[data-role=artist-card]", count: 1)
      |> click_button("Next »")
      |> assert_has("[data-role=artist-card]", count: 1)
      |> click_button("Next »")
      |> assert_has("[data-role=artist-card]", count: 1)
      |> assert_has("button[disabled]", text: "Next »")
    end

    test "results can be reordered through the native select change event", %{conn: conn} do
      artist1 = generate(artist(name: "gamma"))
      generate(album(artist_id: artist1.id, year_released: 2025))

      artist2 = generate(artist(name: "beta"))
      generate_many(album(artist_id: artist2.id, year_released: 2023), 3)

      generate(artist(name: "omega"))

      artist4 = generate(artist(name: "alpha"))
      generate_many(album(artist_id: artist4.id, year_released: 2024), 2)

      conn
      |> visit(~p"/")
      |> select("sort by:", option: "number of albums")
      |> assert_path("/", query_params: %{sort_by: "-album_count"})
      |> visit(~p"/?sort_by=-album_count")
      |> assert_ordered_artists(["beta", "alpha", "gamma", "omega"])
      |> select("sort by:", option: "name")
      |> assert_path("/", query_params: %{sort_by: "name"})
      |> visit(~p"/?sort_by=name")
      |> assert_ordered_artists(["alpha", "beta", "gamma", "omega"])
      |> select("sort by:", option: "latest album release")
      |> assert_path("/", query_params: %{sort_by: "--latest_album_year_released"})
      |> visit(~p"/?sort_by=--latest_album_year_released")
      |> assert_ordered_artists(["gamma", "alpha", "beta", "omega"])
    end

    test "results can be searched", %{conn: conn} do
      generate(artist(name: "gamma"))
      generate(artist(name: "beta"))
      generate(artist(name: "omega"))
      generate(artist(name: "alpha"))

      conn
      |> visit(~p"/")
      |> fill_in("Search", with: "e")
      |> submit()
      |> assert_path("/", query_params: %{q: "e", sort_by: "-updated_at"})
      |> visit(~p"/?q=e&sort_by=-updated_at")
      |> assert_ordered_artists(["omega", "beta"])
    end
  end

  defp assert_ordered_artists(session, names) do
    names
    |> Enum.with_index(1)
    |> Enum.each(fn {name, index} ->
      assert_has(session, "[data-role='artist-name']", text: name, at: index)
    end)

    session
  end
end
