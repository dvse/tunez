defmodule TunezWeb.DatastarModeTest do
  use TunezWeb.ConnCase, async: false

  alias AshBlueprint.Datastar.Store

  test "GET /ds/ mounts the artist index with bindings and the shared session", %{conn: conn} do
    conn = get(conn, "/ds/")
    body = html_response(conn, 200)

    assert body =~ ~s(src="/ds/_ash_blueprint/datastar.js")
    # Datastar's minimal-attribute contract embeds binding keys in data-on dispatch URLs.
    assert body =~ ~r{data-on:[^=]+="[^"]*/ds/_ash_blueprint/dispatch/}
    refute body =~ "data-blueprint-binding"

    assert Enum.any?(get_resp_header(conn, "set-cookie"), fn cookie ->
             String.starts_with?(cookie, "_tunez_key=")
           end)

    session_id = get_session(conn, "ash_blueprint_session_id")
    assert is_binary(session_id)
    assert Store.get(session_id).resource == Tunez.UI.ArtistIndexPage
  end

  test "a real search binding dispatch returns an SSE patch with the new query", %{conn: conn} do
    mount = get(conn, "/ds/")
    body = html_response(mount, 200)
    session_id = get_session(mount, "ash_blueprint_session_id")

    search_input = body |> Floki.parse_document!() |> Floki.find("input#search-text") |> hd()
    [input_expression] = Floki.attribute(search_input, "data-on:input")

    [_, encoded_binding] =
      Regex.run(~r{/ds/_ash_blueprint/dispatch/([^&'"),\s]+)}, input_expression)

    binding_key = URI.decode(encoded_binding)
    search_value = "datastar-search-value"

    response =
      mount
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/ds/_ash_blueprint/dispatch/" <> URI.encode(binding_key),
        Jason.encode!(%{"datastar" => %{binding_key => search_value}})
      )

    assert response.status == 200, response.resp_body
    assert get_resp_header(response, "content-type") == ["text/event-stream"]
    assert response.resp_body =~ "datastar-patch-elements"
    assert response.resp_body =~ search_value
    assert Store.get(session_id).record.q == search_value
  end

  test "an unknown binding returns the explicit stale-binding error", %{conn: conn} do
    mount = get(conn, "/ds/")
    assert html_response(mount, 200)

    response =
      mount
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post("/ds/_ash_blueprint/dispatch/not-a-live-key", "{}")

    assert response.status == 404
    assert response.resp_body =~ "unknown_or_stale_binding"
  end

  test "a signed-in session renders the user menu", %{conn: conn} do
    user = generate(user(email: "datastar-user@example.com"))

    body =
      conn
      |> log_in_user(user)
      |> get("/ds/")
      |> html_response(200)

    assert body =~ ~s(id="user-menu")
    assert body =~ "Signed in as"
    assert body =~ to_string(user.email)
  end
end
