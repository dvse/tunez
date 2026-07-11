defmodule TunezWeb.AuthenticationTest do
  use TunezWeb.ConnCase, async: true

  test "register for a new account", %{conn: conn} do
    email = "newaccount@sevenseacat.net"

    conn
    |> visit(~p"/")
    |> click_link("Register")
    |> within(
      "#register-form",
      fn session ->
        session
        |> fill_in("Email", with: email)
        |> fill_in("Password", with: "password")
        |> fill_in("Password Confirmation", with: "password")
        |> click_button("Register")
      end
    )
    |> assert_path(~p"/")
    |> assert_has(flash(:info), text: "You are now signed in")
    |> assert_has("strong", text: email)

    assert {:ok, user} = Tunez.Accounts.get_user_by_email(email, authorize?: false)
    assert to_string(user.email) == email
  end

  test "sign in to an existing account", %{conn: conn} do
    generate(user(email: "other@sevenseacat.net", password: "password"))

    conn
    |> visit(~p"/")
    |> click_link("Sign In")
    |> within(
      "#sign-in-form",
      fn session ->
        session
        |> fill_in("Email", with: "other@sevenseacat.net")
        |> fill_in("Password", with: "password")
        |> click_button("Sign in")
      end
    )
    |> assert_path(~p"/")
    |> assert_has(flash(:info), text: "You are now signed in")
    |> assert_has("strong", text: "other@sevenseacat.net")
  end

  test "wrong password returns to the Blueprint sign-in page with an error flash", %{conn: conn} do
    generate(user(email: "wrong-password@sevenseacat.net", password: "password"))

    conn
    |> visit(~p"/sign-in")
    |> within("#sign-in-form", fn session ->
      session
      |> fill_in("Email", with: "wrong-password@sevenseacat.net")
      |> fill_in("Password", with: "not-the-password")
      |> click_button("Sign in")
    end)
    |> assert_path(~p"/sign-in")
    |> assert_has(flash(:error), text: "Incorrect email or password")
  end

  test "auth pages mount through the Datastar bridge", %{conn: conn} do
    pages = [
      {"/ds/sign-in", "#sign-in-form"},
      {"/ds/register", "#register-form"},
      {"/ds/reset", "#reset-request-form"},
      {"/ds/confirm_new_user?token=confirm-token", "#confirm-form"},
      {"/ds/magic_link?token=magic-token", "#magic-sign-in-form"}
    ]

    Enum.each(pages, fn {path, form_selector} ->
      body = conn |> Phoenix.ConnTest.recycle() |> get(path) |> html_response(200)
      document = Floki.parse_document!(body)

      assert [_form] = Floki.find(document, form_selector)
      assert [_csrf] = Floki.find(document, "#{form_selector} input[name='_csrf_token']")
    end)
  end
end
