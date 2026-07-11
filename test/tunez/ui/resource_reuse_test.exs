defmodule Tunez.UI.ResourceReuseTest do
  use ExUnit.Case, async: true

  @pages [
    Tunez.UI.AlbumFormPage,
    Tunez.UI.ArtistFormPage,
    Tunez.UI.ArtistIndexPage,
    Tunez.UI.ArtistShowPage
  ]

  @resource_parents @pages ++
                      [
                        Tunez.UI.AppShell,
                        Tunez.UI.ArtistCard,
                        Tunez.UI.FormControl,
                        Tunez.UI.NotificationsPage,
                        Tunez.UI.PageHeader
                      ]

  test "shared resources retain every parent in the compiled resource graph" do
    parents_by_child =
      Enum.reduce(@resource_parents, %{}, fn parent, graph ->
        parent
        |> AshBlueprint.compile!()
        |> Map.fetch!(:view)
        |> child_resources()
        |> Enum.reduce(graph, fn child, graph ->
          Map.update(graph, child, MapSet.new([parent]), &MapSet.put(&1, parent))
        end)
      end)

    assert Map.fetch!(parents_by_child, Tunez.UI.AppShell) == MapSet.new(@pages)

    assert Map.fetch!(parents_by_child, Tunez.UI.FlashStack) ==
             MapSet.new([Tunez.UI.AppShell])

    assert Map.fetch!(parents_by_child, Tunez.UI.FormControl) ==
             MapSet.new([
               Tunez.UI.AlbumFormPage,
               Tunez.UI.ArtistFormPage,
               Tunez.UI.ArtistIndexPage
             ])

    assert Map.fetch!(parents_by_child, Tunez.UI.PageHeader) == MapSet.new(@pages)

    assert Map.fetch!(parents_by_child, Tunez.UI.CoverImage) ==
             MapSet.new([
               Tunez.UI.ArtistCard,
               Tunez.UI.ArtistShowPage,
               Tunez.UI.NotificationsPage
             ])

    assert Map.fetch!(parents_by_child, Tunez.UI.ArtistCard) ==
             MapSet.new([Tunez.UI.ArtistIndexPage])

    assert Map.fetch!(parents_by_child, Tunez.UI.NotificationsPage) ==
             MapSet.new([Tunez.UI.AppShell])
  end

  test "authored UI has no slot, fill, or outlet boundary" do
    source =
      "lib/tunez/ui/**/*.ex"
      |> Path.wildcard()
      |> Enum.map_join("\n", &File.read!/1)

    refute source =~ ~r/\b(?:slot|fill|outlet)\s*\(/
  end

  test "Ash UI source stays within 1.2x of the chapter-10 UI" do
    project = Path.expand("../../..", __DIR__)
    upstream = Path.expand("../tunez_upstream", project)

    line_count = fn files ->
      files
      |> Enum.uniq()
      |> Enum.reduce(0, fn file, total ->
        total + length(String.split(File.read!(file), "\n")) - 1
      end)
    end

    blueprint_lines =
      line_count.([
        Path.join(project, "lib/tunez/ui.ex") | Path.wildcard("#{project}/lib/tunez/ui/*.ex")
      ])

    upstream_lines =
      line_count.(
        Path.wildcard("#{upstream}/lib/tunez_web/live/*.ex") ++
          Path.wildcard("#{upstream}/lib/tunez_web/live/**/*.ex") ++
          [
            Path.join(upstream, "lib/tunez_web/components/core_components.ex"),
            Path.join(upstream, "lib/tunez_web/components/layouts.ex")
          ]
      )

    assert blueprint_lines * 5 <= upstream_lines * 6,
           "Ash UI is #{blueprint_lines} LoC; 1.2x chapter-10 is #{div(upstream_lines * 6, 5)}"
  end

  defp child_resources(value) when is_map(value) do
    resources =
      if Map.get(value, :kind) == :resource_component,
        do: [Map.fetch!(value, :resource)],
        else: []

    resources ++ Enum.flat_map(Map.values(value), &child_resources/1)
  end

  defp child_resources(value) when is_list(value),
    do: Enum.flat_map(value, &child_resources/1)

  defp child_resources(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.flat_map(&child_resources/1)

  defp child_resources(_value), do: []
end
