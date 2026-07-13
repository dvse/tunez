defmodule TunezWeb.MCPTest do
  use TunezWeb.ConnCase, async: true

  @embedded_ui_resources [
    Tunez.UI.AlbumTrackRow,
    Tunez.UI.ArtistCard,
    Tunez.UI.CoverImage,
    Tunez.UI.FormControl
  ]

  test "every Tunez domain and resource declares its AshLua surface" do
    domains_and_resources = Ash.Info.domains_and_resources(:tunez)

    assert Map.keys(domains_and_resources) |> MapSet.new() ==
             MapSet.new([Tunez.Accounts, Tunez.Music, Tunez.UI, Tunez.MCP])

    for {domain, resources} <- domains_and_resources do
      assert AshLua.Domain in Spark.extensions(domain)

      for resource <- resources do
        assert AshLua.Resource in Spark.extensions(resource),
               "#{inspect(resource)} does not declare AshLua.Resource"
      end
    end

    for resource <- @embedded_ui_resources do
      assert Ash.Resource.Info.domain(resource) == Tunez.UI
      assert AshLua.Resource in Spark.extensions(resource)
    end

    assert Enum.map(AshLua.Domain.Info.namespaces(Tunez.Accounts), & &1.name) == [
             "accounts.notification"
           ]

    assert AshLua.Domain.Info.namespaces(Tunez.Music)
           |> Enum.map(& &1.name)
           |> MapSet.new() ==
             MapSet.new([
               "music.artist",
               "music.album",
               "music.track",
               "music.artist_follower"
             ])

    assert AshLua.Domain.Info.namespaces(Tunez.UI)
           |> Enum.map(& &1.name)
           |> MapSet.new() ==
             MapSet.new([
               "ui.page_life",
               "ui.app_shell",
               "ui.page_header",
               "ui.flash",
               "ui.flash_stack",
               "ui.artist_index_page",
               "ui.artist_show_page",
               "ui.artist_form_page",
               "ui.album_form_page",
               "ui.notifications_page",
               "ui.confirm_page",
               "ui.magic_sign_in_page",
               "ui.register_page",
               "ui.reset_page",
               "ui.sign_in_page"
             ])
  end

  test "MCP eval surface is composed exactly from the owning domain declarations" do
    entrypoints =
      Tunez.MCP.Actions
      |> AshLua.EvalActions.Info.action_entrypoints()
      |> MapSet.new()

    domain_entrypoints =
      [Tunez.Accounts, Tunez.Music, Tunez.UI]
      |> Enum.flat_map(&AshLua.Domain.Info.namespaces/1)
      |> Enum.flat_map(& &1.actions)
      |> Enum.map(&{&1.resource, &1.action})
      |> MapSet.new()

    assert entrypoints == domain_entrypoints

    assert MapSet.subset?(
             MapSet.new([
               {Tunez.Music.Artist, :browse},
               {Tunez.Music.Artist, :create},
               {Tunez.Music.Artist, :follow},
               {Tunez.Music.Artist, :destroy},
               {Tunez.Music.Album, :create},
               {Tunez.Music.Album, :update},
               {Tunez.Music.Album, :upload_cover},
               {Tunez.Music.Album, :destroy},
               {Tunez.Music.ArtistFollower, :create},
               {Tunez.Music.ArtistFollower, :unfollow},
               {Tunez.Accounts.Notification, :for_user},
               {Tunez.Accounts.Notification, :destroy},
               {Tunez.UI.ArtistIndexPage, :mount},
               {Tunez.UI.ArtistIndexPage, :change_sort},
               {Tunez.UI.ArtistFormPage, :edit},
               {Tunez.UI.ArtistFormPage, :save},
               {Tunez.UI.AlbumFormPage, :mount},
               {Tunez.UI.AlbumFormPage, :edit},
               {Tunez.UI.AlbumFormPage, :add_track},
               {Tunez.UI.AlbumFormPage, :reorder_tracks},
               {Tunez.UI.AlbumFormPage, :save},
               {Tunez.UI.NotificationsPage, :toggle},
               {Tunez.UI.NotificationsPage, :dismiss}
             ]),
             entrypoints
           )
  end

  test "MCP advertises only the AshLua docs and eval boundary", %{conn: conn} do
    actor = generate(user(role: :admin))

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{actor.__metadata__.token}")
      |> rpc(1, "initialize", %{
        "protocolVersion" => "2025-03-26",
        "capabilities" => %{},
        "clientInfo" => %{"name" => "tunez-test", "version" => "1"}
      })

    assert %{
             "result" => %{
               "protocolVersion" => "2025-03-26",
               "serverInfo" => %{"name" => "Tunez"}
             }
           } = Jason.decode!(conn.resp_body)

    [session_id] = get_resp_header(conn, "mcp-session-id")

    response =
      conn
      |> recycle()
      |> put_req_header("mcp-session-id", session_id)
      |> rpc(2, "tools/list", %{})
      |> then(&Jason.decode!(&1.resp_body))

    assert response["result"]["tools"]
           |> Enum.map(& &1["name"])
           |> MapSet.new() == MapSet.new(["tunez_lua_docs", "tunez_lua_eval"])
  end

  test "MCP executes the scoped AshLua surface", %{conn: conn} do
    response =
      conn
      |> rpc(1, "tools/call", %{
        "name" => "tunez_lua_eval",
        "arguments" => %{"input" => %{"script" => "return 6 * 7"}}
      })
      |> then(&Jason.decode!(&1.resp_body))

    assert [%{"type" => "text", "text" => text}] = response["result"]["content"]
    assert %{"result" => 42, "error" => nil, "print_output" => []} = Jason.decode!(text)
  end

  test "MCP reads and drives semantic UI resource actions only through Lua", %{conn: conn} do
    mount = get(conn, "/")
    session_id = get_session(mount, "ash_blueprint_session_id")

    assert is_binary(session_id)

    script = """
    local fields = {"q"}
    local before, err = ui.artist_index_page.for_session({
      input = {session_id = "#{session_id}"},
      fields = fields
    })
    if err ~= nil then return nil, err end

    local updated, err = ui.artist_index_page.set_query({
      input = {session_id = "#{session_id}", q = "Agent Query"},
      fields = fields
    })
    if err ~= nil then return nil, err end

    local after, err = ui.artist_index_page.for_session({
      input = {session_id = "#{session_id}"},
      fields = fields
    })
    if err ~= nil then return nil, err end

    return {before = before, updated = updated, after = after}
    """

    result =
      mount
      |> recycle()
      |> rpc(1, "tools/call", %{
        "name" => "tunez_lua_eval",
        "arguments" => %{"input" => %{"script" => script}}
      })
      |> tool_result!()

    assert result["error"] == nil
    assert [%{"q" => ""}] = result["result"]["before"]
    assert %{"q" => "Agent Query"} = result["result"]["updated"]
    assert [%{"q" => "Agent Query"}] = result["result"]["after"]
  end

  test "MCP creates, edits, and removes embedded album-track draft rows through the parent attribute",
       %{conn: conn} do
    actor = generate(user(role: :admin))
    artist = generate(artist(actor: actor))

    mount =
      conn
      |> log_in_user(actor)
      |> get("/artists/#{artist.id}/albums/new")

    session_id = get_session(mount, "ash_blueprint_session_id")
    subject_id = "artist:#{artist.id}"

    script = """
    local row_fields = { "id", "track_id", "name", "duration", "position" }
    local form_fields = { { tracks = row_fields } }
    local identity = { session_id = "#{session_id}", subject_id = "#{subject_id}" }

    local added, err = ui.album_form_page.add_track({
      input = identity,
      fields = form_fields
    })
    if err ~= nil then return { stage = "add", error = err } end

    local row = added.tracks[1]
    local tracks = {
      {
        id = row.id,
        name = "Opening Signal",
        duration = "3:42"
      }
    }

    local edited, err = ui.album_form_page.edit({
      input = {
        session_id = identity.session_id,
        subject_id = identity.subject_id,
        tracks = tracks
      },
      fields = form_fields
    })
    if err ~= nil then return { stage = "edit", error = err } end

    local removed, err = ui.album_form_page.edit({
      input = {
        session_id = identity.session_id,
        subject_id = identity.subject_id,
        tracks = {}
      },
      fields = form_fields
    })
    if err ~= nil then return { stage = "remove", error = err } end

    return { added = added, edited = edited, removed = removed }
    """

    result =
      mount
      |> recycle()
      |> put_req_header("authorization", "Bearer #{actor.__metadata__.token}")
      |> rpc(1, "tools/call", %{
        "name" => "tunez_lua_eval",
        "arguments" => %{"input" => %{"script" => script}}
      })
      |> tool_result!()

    assert result["error"] == nil

    assert [%{"name" => "", "duration" => "", "position" => 0}] =
             result["result"]["added"]["tracks"]

    assert [%{"name" => "Opening Signal", "duration" => "3:42", "position" => 0}] =
             result["result"]["edited"]["tracks"]

    assert result["result"]["removed"]["tracks"] == []
  end

  test "MCP preserves nested Ash errors from album save", %{conn: conn} do
    actor = generate(user(role: :admin))
    artist = generate(artist(actor: actor))

    mount =
      conn
      |> log_in_user(actor)
      |> get("/artists/#{artist.id}/albums/new")

    session_id = get_session(mount, "ash_blueprint_session_id")

    script = """
    local identity = {
      session_id = "#{session_id}",
      subject_id = "artist:#{artist.id}"
    }

    local added, err = ui.album_form_page.add_track({
      input = identity,
      fields = {{tracks = {"id"}}}
    })
    if err ~= nil then return {stage = "add", error = err} end

    local _, err = ui.album_form_page.edit({
      input = {
        session_id = identity.session_id,
        subject_id = identity.subject_id,
        name = "Invalid Track Album",
        year_released = "2026",
        tracks = {{
          id = added.tracks[1].id,
          name = "Broken Duration",
          duration = "not-a-duration"
        }}
      }
    })
    if err ~= nil then return {stage = "edit", error = err} end

    local _, save_error = ui.album_form_page.save({input = identity})
    return save_error
    """

    result =
      mount
      |> recycle()
      |> put_req_header("authorization", "Bearer #{actor.__metadata__.token}")
      |> rpc(1, "tools/call", %{
        "name" => "tunez_lua_eval",
        "arguments" => %{"input" => %{"script" => script}}
      })
      |> tool_result!()

    assert result["error"] == nil

    assert %{
             "class" => "invalid",
             "errors" => [
               %{
                 "code" => "invalid_attribute",
                 "fields" => ["duration"],
                 "message" => "use MM:SS format"
               }
             ]
           } = result["result"]
  end

  test "MCP Lua actions follow and unfollow through their declared input shape", %{conn: conn} do
    actor = generate(user(role: :admin))
    artist = generate(artist(actor: actor))

    script = """
    local id = "#{artist.id}"
    local fields = {"id", "followed_by_me", "follower_count"}

    local function state()
      local rows, err = music.artist.read({filter = {id = id}, fields = fields})
      if err ~= nil then return nil, err end
      return (rows.results and rows.results[1]) or rows[1], nil
    end

    local before, err = state()
    if err ~= nil then return {stage = "before", error = err} end

    local _, err = music.artist_follower.create({input = {artist_id = id}})
    if err ~= nil then return {stage = "follow", error = err} end

    local followed, err = state()
    if err ~= nil then return {stage = "followed", error = err} end

    local _, err = music.artist_follower.unfollow({input = {artist_id = id}})
    if err ~= nil then return {stage = "unfollow", error = err} end

    local after, err = state()
    if err ~= nil then return {stage = "after", error = err} end

    return {before, followed, after}
    """

    response =
      conn
      |> put_req_header("authorization", "Bearer #{actor.__metadata__.token}")
      |> rpc(1, "tools/call", %{
        "name" => "tunez_lua_eval",
        "arguments" => %{"input" => %{"script" => script}}
      })
      |> then(&Jason.decode!(&1.resp_body))

    assert [%{"type" => "text", "text" => text}] = response["result"]["content"]

    assert %{
             "error" => nil,
             "result" => [
               %{"followed_by_me" => false, "follower_count" => 0},
               %{"followed_by_me" => true, "follower_count" => 1},
               %{"followed_by_me" => false, "follower_count" => 0}
             ]
           } = Jason.decode!(text)
  end

  test "album cover upload confines paths, stores the image, and updates the album" do
    actor = generate(user(role: :admin))
    album = generate(album(actor: actor, cover_image_url: nil))
    upload_root = Application.fetch_env!(:tunez, :mcp_upload_roots) |> hd()
    File.mkdir_p!(upload_root)

    png =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )

    source_path = Path.join(upload_root, "cover-#{System.unique_integer([:positive])}.png")
    File.write!(source_path, png)
    on_exit(fn -> File.rm(source_path) end)

    album =
      Tunez.Music.upload_album_cover!(
        album,
        %{path: source_path},
        actor: actor
      )

    assert album.cover_image_url =~ ~r"^/images/uploads/[0-9a-f]{64}[.]png$"

    path =
      Application.app_dir(
        :tunez,
        "priv/static" <> album.cover_image_url
      )

    assert File.read!(path) == png
    on_exit(fn -> File.rm(path) end)

    assert_raise Ash.Error.Invalid, fn ->
      Tunez.Music.upload_album_cover!(
        album,
        %{path: Path.join(upload_root, "missing.png")},
        actor: actor
      )
    end

    outside_path =
      Path.join(
        System.tmp_dir!(),
        "tunez-outside-cover-#{System.unique_integer([:positive])}.png"
      )

    symlink_path =
      Path.join(upload_root, "cover-link-#{System.unique_integer([:positive])}.png")

    File.write!(outside_path, png)
    File.ln_s!(outside_path, symlink_path)

    on_exit(fn ->
      File.rm(symlink_path)
      File.rm(outside_path)
    end)

    for rejected_path <- [outside_path, symlink_path] do
      assert_raise Ash.Error.Invalid, fn ->
        Tunez.Music.upload_album_cover!(album, %{path: rejected_path}, actor: actor)
      end
    end
  end

  defp rpc(conn, id, method, params) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> post(
      "/mcp",
      Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params})
    )
  end

  defp tool_result!(conn) do
    response = Jason.decode!(conn.resp_body)
    assert [%{"type" => "text", "text" => text}] = response["result"]["content"]
    Jason.decode!(text)
  end
end
