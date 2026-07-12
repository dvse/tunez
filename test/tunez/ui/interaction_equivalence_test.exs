defmodule Tunez.UI.InteractionEquivalenceTest do
  use TunezWeb.ConnCase, async: false

  import Phoenix.LiveViewTest, only: [follow_redirect: 3, live: 2]

  require Phoenix.LiveViewTest

  alias Phoenix.LiveView.Diff, as: LiveDiff
  alias Phoenix.LiveViewTest.Diff, as: LiveClient

  @user_id "10000000-0000-4000-8000-000000000001"
  @artist_ids [
    "20000000-0000-4000-8000-000000000001",
    "20000000-0000-4000-8000-000000000002",
    "20000000-0000-4000-8000-000000000003"
  ]
  @album_id "30000000-0000-4000-8000-000000000001"
  @track_id "40000000-0000-4000-8000-000000000001"
  @notification_id "50000000-0000-4000-8000-000000000001"

  defmodule BackendView do
    @moduledoc false
    defstruct [
      :backend,
      :conn,
      :view,
      :html,
      :path,
      :session_id,
      :last_response,
      :live_client,
      traffic: []
    ]
  end

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

  for backend <- [:phoenix, :datastar] do
    @backend backend

    test "#{backend}: artist catalogue matches empty, populated, sorted, and searched states", %{
      conn: conn,
      upstream: upstream
    } do
      backend = @backend

      assert_parity!(
        upstream,
        "artist_index_empty",
        mount!(build_conn(), "/?q=NO_PARITY_MATCH", backend)
      )

      assert_parity!(
        upstream,
        "artist_index_invalid_sort",
        mount!(build_conn(), "/?sort_by=definitely_invalid", backend)
      )

      populated = mount!(conn, "/?q=Parity&sort_by=name&limit=1&offset=1", backend)
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

      sorted = mount!(conn, "/?q=Parity&sort_by=name", backend)

      sorted
      |> change_form("[data-role='artist-sort']", "-album_count")
      |> assert_parity!(upstream, "artist_index_sorted")

      searched = mount!(conn, "/?sort_by=name", backend)

      searched
      |> change_field("#search-text", "Omega")
      |> submit_form("[data-role='artist-search']")
      |> assert_parity!(upstream, "artist_index_searched")
    end

    test "#{backend}: artist details match followed, unfollowed, and refollowed states", %{
      conn: conn,
      upstream: upstream
    } do
      backend = @backend
      artist_id = Enum.at(@artist_ids, 1)
      view = mount!(conn, "/artists/#{artist_id}", backend)

      assert_parity!(
        upstream,
        "artist_show_anonymous",
        mount!(build_conn(), "/artists/#{artist_id}", backend)
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

    test "#{backend}: artist forms match new, edit, mid-edit, error, and recovery states", %{
      conn: conn,
      upstream: upstream
    } do
      backend = @backend
      artist_id = Enum.at(@artist_ids, 1)

      assert_parity!(upstream, "artist_new", mount!(conn, "/artists/new", backend))

      assert_parity!(
        upstream,
        "artist_edit",
        mount!(conn, "/artists/#{artist_id}/edit", backend)
      )

      new_mid_edit = mount!(conn, "/artists/new", backend)

      new_mid_edit
      |> change_field("#artist_form_name", "New Artist Draft")
      |> change_field("#artist_form_biography", "New draft biography")
      |> assert_parity!(upstream, "artist_new_mid_edit")

      new_invalid = mount!(conn, "/artists/new", backend)

      new_invalid
      |> change_field("#artist_form_name", "")
      |> change_field("#artist_form_biography", "Draft")
      |> submit_form("#artist_form")
      |> assert_attribute("#artist_form_name", "aria-invalid", "true")
      |> assert_parity!(upstream, "artist_new_error")
      |> change_field("#artist_form_name", "New Artist Draft")
      |> change_field("#artist_form_biography", "New draft biography")
      |> refute_attribute("#artist_form_name", "aria-invalid", "true")
      |> assert_parity!(upstream, "artist_new_mid_edit")

      mid_edit = mount!(conn, "/artists/#{artist_id}/edit", backend)

      mid_edit
      |> change_field("#artist_form_name", "Parity M83 Draft")
      |> change_field("#artist_form_biography", "Draft biography\nSecond draft line.")
      |> assert_parity!(upstream, "artist_edit_mid_edit")

      invalid = mount!(conn, "/artists/#{artist_id}/edit", backend)

      invalid
      |> change_field("#artist_form_name", "")
      |> change_field("#artist_form_biography", "Draft biography")
      |> submit_form("#artist_form")
      |> assert_parity!(upstream, "artist_edit_error")
      |> change_field("#artist_form_name", "Parity M83 Draft")
      |> change_field("#artist_form_biography", "Draft biography\nSecond draft line.")
      |> refute_attribute("#artist_form_name", "aria-invalid", "true")
      |> assert_parity!(upstream, "artist_edit_mid_edit")
    end

    test "#{backend}: album forms match nested edit, reorder, remove, error, and recovery states",
         %{
           conn: conn,
           upstream: upstream
         } do
      backend = @backend
      artist_id = Enum.at(@artist_ids, 1)

      assert_parity!(
        upstream,
        "album_new",
        mount!(conn, "/artists/#{artist_id}/albums/new", backend)
      )

      assert_parity!(
        upstream,
        "album_edit",
        mount!(conn, "/albums/#{@album_id}/edit", backend)
      )

      mid_edit = mount!(conn, "/artists/#{artist_id}/albums/new", backend)

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
      |> reorder("#trackSort", [1, 0])
      |> assert_parity!(upstream, "album_new_after_reorder")
      |> click("tr[data-id='1'] button[part=track_delete_link]")
      |> assert_parity!(upstream, "album_new_after_remove")

      invalid = mount!(conn, "/artists/#{artist_id}/albums/new", backend)

      invalid
      |> change_field("#album_form_name", "Incomplete Album")
      |> submit_form("#album_form")
      |> assert_attribute("#album_form_year_released", "aria-invalid", "true")
      |> assert_parity!(upstream, "album_new_error")
      |> change_field("#album_form_year_released", "2024")
      |> refute_attribute("#album_form_year_released", "aria-invalid", "true")

      invalid_track = mount!(conn, "/artists/#{artist_id}/albums/new", backend)

      invalid_track
      |> click("a", "Add Track")
      |> change_field("#album_form_name", "Invalid Track Album")
      |> change_field("#album_form_year_released", "2024")
      |> change_field("#album_form_cover_image_url", "/images/invalid-track.jpg")
      |> change_field("#album_form_tracks_0_name", "Broken Duration")
      |> change_field("#album_form_tracks_0_duration", "bad")
      |> submit_form("#album_form")
      |> assert_parity!(upstream, "album_new_track_error")
      |> change_field("#album_form_tracks_0_duration", "4:04")
      |> refute_attribute("#album_form_tracks_0_duration", "aria-invalid", "true")

      edit_mid = mount!(conn, "/albums/#{@album_id}/edit", backend)

      edit_mid
      |> change_field("#album_form_name", "Edited Album Draft")
      |> change_field("#album_form_year_released", "2023")
      |> change_field("#album_form_cover_image_url", "/images/edited-draft.jpg")
      |> change_field("#album_form_tracks_0_name", "Edited Track Draft")
      |> change_field("#album_form_tracks_0_duration", "5:05")
      |> assert_parity!(upstream, "album_edit_mid_edit")

      edit_invalid = mount!(conn, "/albums/#{@album_id}/edit", backend)

      edit_invalid
      |> change_field("#album_form_name", "")
      |> submit_form("#album_form")
      |> assert_parity!(upstream, "album_edit_error")
      |> change_field("#album_form_name", "Edited Album Draft")
      |> refute_attribute("#album_form_name", "aria-invalid", "true")
    end

    test "#{backend}: successful edits persist, navigate, and match upstream flash states", %{
      conn: conn,
      upstream: upstream
    } do
      backend = @backend
      artist_id = Enum.at(@artist_ids, 1)
      conn = Plug.Conn.put_session(conn, "ash_blueprint_session_id", Ash.UUID.generate())

      artist_show =
        conn
        |> mount!("/artists/#{artist_id}/edit", backend)
        |> change_field("#artist_form_name", "Parity M83 Saved")
        |> change_field("#artist_form_biography", "Saved biography\nSaved second line.")
        |> submit_and_follow("#artist_form", "/artists/#{artist_id}")

      assert_parity!(upstream, "artist_edit_success", artist_show)

      artist = Tunez.Music.get_artist_by_id!(artist_id)
      assert artist.name == "Parity M83 Saved"
      assert artist.biography == "Saved biography\nSaved second line."

      album_show =
        conn
        |> mount!("/albums/#{@album_id}/edit", backend)
        |> change_field("#album_form_name", "Saved Album")
        |> change_field("#album_form_year_released", "2025")
        |> change_field("#album_form_cover_image_url", "/images/saved.jpg")
        |> change_field("#album_form_tracks_0_name", "Saved Track")
        |> change_field("#album_form_tracks_0_duration", "6:06")
        |> submit_and_follow("#album_form", "/artists/#{artist_id}")

      assert_parity!(upstream, "album_edit_success", album_show)

      album = Tunez.Music.get_album_by_id!(@album_id, load: [:tracks])
      assert album.name == "Saved Album"
      assert album.year_released == 2025
      assert album.cover_image_url == "/images/saved.jpg"
      assert Enum.map(album.tracks, &{&1.name, &1.duration_seconds}) == [{"Saved Track", 366}]
    end
  end

  defp assert_parity!(%BackendView{} = view, upstream, scenario)
       when is_map(upstream) and is_binary(scenario) do
    assert_parity!(upstream, scenario, view)
    view
  end

  defp assert_parity!(upstream, scenario, %BackendView{} = view)
       when is_map(upstream) and is_binary(scenario) do
    Tunez.HTMLParity.assert_app_same!(
      Map.fetch!(upstream, scenario),
      render(view),
      "#{view.backend}: #{scenario}"
    )
  end

  defp mount!(conn, path, :phoenix) do
    # dispatch first so the returned conn carries the blueprint session
    # cookie: within one BackendView chain the session persists across
    # redirects (browser-faithful); separate mount! calls on the base
    # conn stay session-isolated.
    conn = get(conn, path)
    {:ok, view, _html} = Phoenix.LiveViewTest.live(conn)

    %BackendView{
      backend: :phoenix,
      conn: conn,
      view: view,
      html: Phoenix.LiveViewTest.render(view),
      path: path
    }
  end

  defp mount!(conn, path, :datastar) do
    response = get(conn, datastar_path(path))
    html = html_response(response, 200)
    session_id = get_session(response, "ash_blueprint_session_id")
    state = AshBlueprint.Datastar.Store.get(session_id)
    live_client = LiveClient.merge_diff(%{}, state.live.diff)
    liveview_dom = Tunez.HTMLParity.normalize(datastar_root(liveview_html(live_client)))
    datastar_dom = Tunez.HTMLParity.normalize(datastar_root(html))

    assert liveview_dom == datastar_dom,
           "Datastar mount differs from its native LiveView render: #{inspect(first_tree_difference(Floki.parse_fragment!(liveview_dom), Floki.parse_fragment!(datastar_dom), []), printable_limit: 2_000)}"

    %BackendView{
      backend: :datastar,
      conn: response,
      html: html,
      path: path,
      session_id: session_id,
      live_client: live_client,
      last_response: response
    }
  end

  defp change_field(%BackendView{} = view, selector, value) do
    dispatch_event(view, selector, :input, %{"value" => value})
  end

  defp change_form(%BackendView{} = view, selector, value) do
    dispatch_event(view, selector, :change, %{"value" => value})
  end

  defp submit_form(%BackendView{} = view, selector) do
    dispatch_event(view, selector, :submit, %{})
  end

  defp submit_and_follow(%BackendView{backend: :phoenix} = view, selector, path) do
    binding = binding_key!(view, selector, :submit)

    result =
      Phoenix.LiveViewTest.render_hook(
        view.view,
        "ash_blueprint:dispatch",
        %{"binding" => binding}
      )

    {:ok, next_view, _html} = follow_redirect(result, view.conn, path)

    %BackendView{
      view
      | view: next_view,
        html: Phoenix.LiveViewTest.render(next_view),
        path: path,
        last_response: result
    }
  end

  defp submit_and_follow(%BackendView{backend: :datastar} = view, selector, path) do
    view = dispatch_event(view, selector, :submit, %{})
    expected = "window.location.assign(#{Jason.encode!(datastar_path(path))})"

    assert view.last_response.resp_body =~ expected,
           "expected Datastar navigation script #{expected}, got:\n#{view.last_response.resp_body}"

    mount!(Phoenix.ConnTest.recycle(view.last_response), path, :datastar)
  end

  defp click(%BackendView{} = view, selector, text \\ nil) do
    dispatch_event(view, selector, :click, %{}, text)
  end

  defp click_away(%BackendView{} = view, selector) do
    dispatch_event(view, selector, :click_away, %{})
  end

  defp reorder(%BackendView{} = view, selector, order) do
    dispatch_event(view, selector, :reorder, %{"order" => order})
  end

  defp assert_attribute(%BackendView{} = view, selector, name, value) do
    values = view |> render() |> attributes(selector, name)

    assert value in values,
           "expected #{view.backend} #{selector} to have #{name}=#{value}, got #{inspect(values)}"

    view
  end

  defp refute_attribute(%BackendView{} = view, selector, name, value) do
    values = view |> render() |> attributes(selector, name)
    refute value in values

    view
  end

  defp dispatch_event(%BackendView{} = view, selector, event, payload, text \\ nil) do
    binding = binding_key!(view, selector, event, text)
    dispatch_binding(view, binding, event, payload)
  end

  defp dispatch_binding(%BackendView{backend: :phoenix} = view, binding, _event, payload) do
    result =
      Phoenix.LiveViewTest.render_hook(
        view.view,
        "ash_blueprint:dispatch",
        Map.put(payload, "binding", binding)
      )

    %{view | html: Phoenix.LiveViewTest.render(view.view), last_response: result}
  end

  defp dispatch_binding(%BackendView{backend: :datastar} = view, binding, event, payload) do
    signals = datastar_signals(binding, event, payload)
    before_html = render(view)

    response =
      view.conn
      |> Phoenix.ConnTest.recycle()
      |> put_req_header("accept-encoding", "identity")
      |> put_req_header("content-type", "application/json")
      |> post(
        "/ds/_ash_blueprint/dispatch/" <> URI.encode(binding),
        Jason.encode!(%{"datastar" => signals})
      )

    assert response.status == 200, response.resp_body
    assert get_resp_header(response, "content-type") == ["text/event-stream"]

    traffic = sse_events(response.resp_body)

    if Enum.any?(traffic, &navigation_effect?/1) do
      assert Enum.filter(traffic, &view_patch?/1) == [],
             "#{event} emitted view patches alongside hard navigation: #{inspect(traffic)}"

      %{view | conn: response, last_response: response, traffic: traffic}
    else
      after_state = AshBlueprint.Datastar.Store.get(view.session_id)
      canonical = render_datastar(view.session_id)
      html = apply_datastar_traffic(before_html, traffic)
      liveview_diff = after_state.live.diff
      live_client = LiveClient.merge_diff(view.live_client, liveview_diff)

      assert_scoped_datastar_traffic!(before_html, canonical, traffic, event)
      assert_datastar_traffic_equivalent!(html, canonical, traffic, event)

      assert_liveview_datastar_traffic_equivalent!(
        liveview_diff,
        liveview_html(live_client),
        canonical,
        traffic,
        event
      )

      %{
        view
        | conn: response,
          html: html,
          live_client: live_client,
          last_response: response,
          traffic: traffic
      }
    end
  end

  defp datastar_signals(binding, event, %{"value" => value})
       when event in [:input, :change],
       do: %{binding => value}

  defp datastar_signals(binding, _event, payload), do: %{binding => payload}

  defp render(%BackendView{backend: :phoenix, view: view}),
    do: Phoenix.LiveViewTest.render(view)

  defp render(%BackendView{backend: :datastar, html: html}), do: html

  defp render_datastar(session_id) do
    state = AshBlueprint.Datastar.Store.get(session_id)

    AshBlueprint.Datastar.FragmentRender.full_render(state.record, state.table,
      actor: state.actor,
      tenant: state.tenant,
      context: state.context,
      session_id: session_id,
      params: state.params,
      base_path: "/ds",
      errors: Map.get(state, :errors, [])
    )
  end

  defp liveview_html(client) do
    client
    |> Map.delete(:streams)
    |> LiveDiff.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp binding_key!(%BackendView{} = view, selector, event, text \\ nil) do
    node = target_node!(view, selector, text)
    attribute = "data-blueprint-binding-" <> event_attribute_name(event)

    case Floki.attribute([node], attribute) do
      [binding] when binding != "" -> binding
      values -> raise "expected one #{attribute} on #{selector}, got #{inspect(values)}"
    end
  end

  defp event_attribute_name(event), do: event |> to_string() |> String.replace("_", "-")

  defp target_node!(%BackendView{} = view, selector, text) do
    nodes = view |> render() |> Floki.parse_document!() |> Floki.find(selector)

    nodes =
      if is_binary(text) do
        Enum.filter(nodes, &(Floki.text(&1) |> String.contains?(text)))
      else
        nodes
      end

    case nodes do
      [node] -> node
      nodes -> raise "expected one #{view.backend} node for #{selector}, got #{length(nodes)}"
    end
  end

  defp attributes(html, selector, name) do
    html |> Floki.parse_document!() |> Floki.find(selector) |> Floki.attribute(name)
  end

  defp sse_events(body) do
    body
    |> String.split("\n\n", trim: true)
    |> Enum.map(fn event ->
      lines = String.split(event, "\n")

      %{
        raw: event <> "\n\n",
        type: line_value(lines, "event: "),
        selector: line_value(lines, "data: selector "),
        mode: line_value(lines, "data: mode ") || "outer",
        elements:
          lines
          |> Enum.filter(&String.starts_with?(&1, "data: elements "))
          |> Enum.map(&String.replace_prefix(&1, "data: elements ", ""))
          |> Enum.join("\n")
      }
    end)
  end

  defp line_value(lines, prefix) do
    Enum.find_value(lines, fn line ->
      if String.starts_with?(line, prefix), do: String.replace_prefix(line, prefix, "")
    end)
  end

  defp apply_datastar_traffic(html, traffic) do
    tree = Floki.parse_document!(html)

    traffic
    |> Enum.filter(&view_patch?/1)
    |> Enum.reduce(tree, &apply_datastar_event/2)
    |> Floki.raw_html(encode: false)
  end

  defp apply_datastar_event(%{selector: selector, mode: mode, elements: elements}, tree) do
    assert is_binary(selector), "Datastar view patches must be selector-scoped"

    replacement = Floki.parse_fragment!(elements)
    tree = maybe_remove_moved_elements(tree, replacement, mode)
    assert [_target] = Floki.find(tree, selector)
    id = selector |> String.trim_leading("#") |> String.replace("\\", "")

    Floki.traverse_and_update(tree, fn
      {tag, attrs, children} = node ->
        if List.keyfind(attrs, "id", 0) == {"id", id} do
          case mode do
            "outer" -> replacement
            "replace" -> replacement
            "remove" -> nil
            "inner" -> {tag, attrs, replacement}
            "append" -> {tag, attrs, children ++ replacement}
            "prepend" -> {tag, attrs, replacement ++ children}
            "before" -> replacement ++ [node]
            "after" -> [node | replacement]
          end
        else
          node
        end

      node ->
        node
    end)
  end

  defp maybe_remove_moved_elements(tree, replacement, mode)
       when mode in ["append", "prepend", "before", "after"] do
    ids =
      for {_tag, attrs, _children} <- replacement,
          {"id", id} <- attrs,
          do: id

    Floki.traverse_and_update(tree, fn
      {_tag, attrs, _children} = node ->
        case List.keyfind(attrs, "id", 0) do
          {"id", id} -> if(id in ids, do: nil, else: node)
          _other -> node
        end

      node ->
        node
    end)
  end

  defp maybe_remove_moved_elements(tree, _replacement, _mode), do: tree

  defp assert_scoped_datastar_traffic!(before_html, canonical, traffic, event) do
    patches = Enum.filter(traffic, &view_patch?/1)

    if patches == [] do
      assert datastar_root(before_html) == datastar_root(canonical),
             "#{event} emitted no view patch although the Datastar view changed: #{inspect(traffic)}"
    else
      assert Enum.all?(patches, &is_binary(&1.selector)),
             "#{event} emitted an unscoped full-root Datastar replacement: #{inspect(patches)}"

      assert Enum.all?(patches, &String.starts_with?(&1.selector, "#")),
             "#{event} emitted a non-element Datastar selector: #{inspect(patches)}"

      selectors = Enum.map(patches, & &1.selector)
      assert Enum.uniq(selectors) == selectors, "#{event} emitted duplicate Datastar selectors"

      redundant =
        for outer <- patches,
            inner <- patches,
            outer != inner,
            inner_id = String.trim_leading(inner.selector, "#"),
            inner_id in (outer.elements
                         |> Floki.parse_fragment!()
                         |> Floki.find("[id]")
                         |> Floki.attribute("id")),
            do: {outer.selector, inner.selector}

      assert redundant == [],
             "#{event} emitted descendant patches already contained by ancestor fragments: #{inspect(redundant)}"
    end
  end

  defp assert_datastar_traffic_equivalent!(patched, canonical, traffic, event) do
    patched = datastar_root(patched)
    canonical = datastar_root(canonical)

    assert patched == canonical,
           "#{event} Datastar SSE fragments do not reconstruct the canonical resource view: #{inspect(%{difference: first_tree_difference(Floki.parse_fragment!(patched), Floki.parse_fragment!(canonical), []), patches: Enum.map(Enum.filter(traffic, &view_patch?/1), &{&1.selector, String.contains?(&1.elements, "is required")})}, printable_limit: 2_000)}"
  end

  defp assert_liveview_datastar_traffic_equivalent!(
         liveview_diff,
         liveview_html,
         datastar_html,
         traffic,
         event
       ) do
    patches = Enum.filter(traffic, &view_patch?/1)
    liveview_regions = liveview_payload_count(liveview_diff)

    liveview_dom = Tunez.HTMLParity.normalize(datastar_root(liveview_html))
    datastar_dom = Tunez.HTMLParity.normalize(datastar_root(datastar_html))

    assert liveview_dom == datastar_dom,
           "#{event} produced different LiveView and Datastar DOM states: #{inspect(first_tree_difference(Floki.parse_fragment!(liveview_dom), Floki.parse_fragment!(datastar_dom), []), printable_limit: 2_000)}"

    if patches == [] do
      assert liveview_diff == %{},
             "#{event} emitted LiveView traffic but no Datastar view traffic: #{inspect(liveview_diff)}"
    else
      assert liveview_diff != %{},
             "#{event} emitted Datastar fragments but no LiveView differential traffic"

      datastar_bytes = patches |> Enum.map(&byte_size(&1.raw)) |> Enum.sum()
      liveview_bytes = liveview_wire_bytes(liveview_diff)

      assert length(patches) <= max(liveview_regions, 1),
             "#{event} used #{length(patches)} Datastar regions/#{datastar_bytes}B versus #{liveview_regions} LiveView payload regions/#{liveview_bytes}B"

      assert datastar_bytes > 0 and liveview_bytes > 0,
             "#{event} did not produce measurable Datastar and LiveView wire traffic"
    end
  end

  defp liveview_wire_bytes(diff) do
    reply = %Phoenix.Socket.Reply{
      join_ref: "1",
      ref: "1",
      topic: "lv:oracle",
      status: :ok,
      payload: %{diff: diff}
    }

    {:socket_push, :text, wire} = Phoenix.Socket.V2.JSONSerializer.encode!(reply)
    wire |> IO.iodata_to_binary() |> byte_size()
  end

  defp liveview_payload_count(nil), do: 0

  defp liveview_payload_count(%{} = diff) do
    Enum.reduce(diff, 0, fn
      {key, _value}, count when key in [:s, :p, :r] -> count
      {_key, value}, count -> count + liveview_payload_count(value)
    end)
  end

  defp liveview_payload_count(list) when is_list(list),
    do: Enum.reduce(list, 0, &(liveview_payload_count(&1) + &2))

  defp liveview_payload_count(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> liveview_payload_count()

  defp liveview_payload_count(_leaf), do: 1

  defp view_patch?(%{type: "datastar-patch-elements", elements: elements}) do
    not String.starts_with?(String.trim_leading(elements), "<script")
  end

  defp view_patch?(_event), do: false

  defp navigation_effect?(%{type: "datastar-patch-elements", elements: elements}),
    do: elements =~ "window.location.assign"

  defp navigation_effect?(_event), do: false

  defp datastar_root(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[part='app_root']")
    |> case do
      [root] -> Floki.raw_html([root], encode: false)
      roots -> raise "expected one Datastar app root, got #{length(roots)}"
    end
  end

  defp first_tree_difference(left, right, _path) when left == right, do: nil

  defp first_tree_difference(left, right, path) when is_list(left) and is_list(right) do
    if length(left) == length(right) do
      left
      |> Enum.zip(right)
      |> Enum.with_index()
      |> Enum.find_value(fn {{left, right}, index} ->
        first_tree_difference(left, right, path ++ [index])
      end)
    else
      %{path: path, left_count: length(left), right_count: length(right)}
    end
  end

  defp first_tree_difference(
         {tag, left_attrs, left_children},
         {tag, right_attrs, right_children},
         path
       ) do
    if Map.new(left_attrs) == Map.new(right_attrs) do
      first_tree_difference(left_children, right_children, path ++ [tag])
    else
      %{path: path ++ [tag], left_attrs: left_attrs, right_attrs: right_attrs}
    end
  end

  defp first_tree_difference(left, right, path),
    do: %{path: path, left: left, right: right}

  defp datastar_path("/" <> _rest = path), do: "/ds" <> path
  defp datastar_path(path), do: "/ds/" <> path

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
