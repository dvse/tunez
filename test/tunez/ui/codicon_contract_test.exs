defmodule Tunez.UI.CodiconContractTest do
  use TunezWeb.ConnCase, async: true

  @shared_icons "../app_domain_workbench/priv/theme/styles/vscode/10-vscode-icons.css"
  @app_css "priv/static/assets/app.css"

  @routed_resources [
    Tunez.UI.AlbumFormPage,
    Tunez.UI.ArtistFormPage,
    Tunez.UI.ArtistIndexPage,
    Tunez.UI.ArtistShowPage,
    Tunez.UI.ConfirmPage,
    Tunez.UI.MagicSignInPage,
    Tunez.UI.RegisterPage,
    Tunez.UI.ResetPage,
    Tunez.UI.SignInPage
  ]

  @icon_resources [
    Tunez.UI.AlbumTrackRow,
    Tunez.UI.AppShell,
    Tunez.UI.ArtistCard,
    Tunez.UI.ArtistIndexPage,
    Tunez.UI.ArtistShowPage,
    Tunez.UI.ConfirmPage,
    Tunez.UI.CoverImage,
    Tunez.UI.FlashStack,
    Tunez.UI.FormControl,
    Tunez.UI.MagicSignInPage,
    Tunez.UI.NotificationsPage,
    Tunez.UI.PageHeader
  ]

  @static_icons %{
    brand_icon: ["music"],
    empty_icon: ["circle-slash"],
    field_error_icon: List.duplicate("error", 5),
    flash_close_icon: List.duplicate("close", 4),
    flash_kind_icon: List.duplicate("error", 3),
    flash_spinner: List.duplicate("loading", 2),
    follow_toggle_icon: ["star", "star-full"],
    followed_icon: ["star-full"],
    follower_count_icon: ["star"],
    missing_cover_icon: ["file-media"],
    notifications_bell_icon: ["bell-dot"],
    notifications_empty_icon: ["pass-filled"],
    page_header_toggle_icon: ["chevron-down"],
    search_icon: ["search"],
    track_delete_icon: ["trash"],
    track_editor_handle: ["grabber"],
    tracks_empty_icon: ["clock"]
  }

  @codicons ~w(
    bell-dot chevron-down circle-slash clock close error file-media grabber loading music
    pass-filled search star star-full trash warning
  )

  test "all semantic icon parts compile to the exact Codicon contract" do
    icons =
      @icon_resources
      |> Enum.flat_map(fn resource ->
        resource
        |> AshBlueprint.compile!()
        |> Map.fetch!(:view)
        |> icon_nodes()
      end)
      |> Enum.group_by(& &1.part, &Map.fetch!(&1.attrs, "data-icon"))

    assert Map.keys(icons) |> Enum.sort() == Map.keys(@static_icons) |> Enum.sort()

    Enum.each(@static_icons, fn {part, expected} ->
      {dynamic, static} = Enum.split_with(Map.fetch!(icons, part), &is_struct(&1))

      assert Enum.sort(static) == Enum.sort(expected),
             "unexpected static data-icon values for #{inspect(part)}"

      case part do
        :flash_kind_icon ->
          assert [
                   %AshBlueprint.Expr.Compiled{
                     source: source,
                     deps: [item: [:flash, [:kind]]]
                   }
                 ] = dynamic

          assert source =~ ~s({:_item, :flash, [:kind]} == :info ->\n    "pass-filled")
          assert source =~ ~s({:_item, :flash, [:kind]} == :error ->\n    "error")
          assert source =~ ~s(true ->\n    "warning")

        _part ->
          assert dynamic == []
      end
    end)
  end

  test "every routed resource loads the shared icon sheet before app paint" do
    Enum.each(@routed_resources, fn resource ->
      assert AshBlueprint.Info.declared_stylesheets(resource) == [@shared_icons, @app_css]
      assert AshBlueprint.Info.stylesheets(resource) == [@shared_icons, @app_css]
    end)
  end

  test "the endpoint serves only the shared theme style and font trees", %{conn: conn} do
    conn =
      get(
        conn,
        "/app_domain_workbench/priv/theme/styles/vscode/10-vscode-icons.css"
      )

    sheet = response(conn, 200)
    assert sheet =~ "font-family: 'codicon'"

    Enum.each(@codicons, fn icon ->
      assert sheet =~ ~s([part][data-icon="#{icon}"]::before)
    end)

    conn =
      build_conn()
      |> get("/app_domain_workbench/priv/theme/fonts/codicon.ttf")

    assert byte_size(response(conn, 200)) > 1_000

    conn =
      build_conn()
      |> get("/app_domain_workbench/priv/theme/codicons.json")

    assert response(conn, 404)
  end

  test "owned source and compiled paint contain no Heroicon or mask remnants" do
    project = Path.expand("../../..", __DIR__)

    files =
      [
        Path.join(project, "mix.exs"),
        Path.join(project, "mix.lock"),
        Path.join(project, "priv/static/assets/app.css")
      ] ++
        Path.wildcard(Path.join(project, "assets/**/*.{css,js}")) ++
        Path.wildcard(Path.join(project, "lib/**/*.ex"))

    source = Enum.map_join(files, "\n", &File.read!/1)

    refute source =~ ~r/heroicons|hero-|--hero-/i
    refute source =~ ~r/(?:-webkit-)?mask\s*:/i
    refute source =~ ~r/data:image\/svg|<svg/i
    refute File.exists?(Path.join(project, "assets/vendor/heroicons.js"))
  end

  defp icon_nodes(%{kind: :element, part: part, attrs: attrs} = node) do
    own =
      if Map.has_key?(@static_icons, part) do
        [node]
      else
        []
      end

    own ++ icon_nodes(Map.values(Map.delete(node, :meta))) ++ icon_nodes(attrs)
  end

  defp icon_nodes(value) when is_map(value), do: value |> Map.values() |> icon_nodes()
  defp icon_nodes(value) when is_list(value), do: Enum.flat_map(value, &icon_nodes/1)
  defp icon_nodes(value) when is_tuple(value), do: value |> Tuple.to_list() |> icon_nodes()
  defp icon_nodes(_value), do: []
end
