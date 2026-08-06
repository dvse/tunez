defmodule TunezWeb.Auth do
  @moduledoc """
  Host plumbing for the AshAuthentication strategy routes.

  `auth_routes/3` and `sign_out_route/1` forward to a module that implements the
  `AshAuthentication.Phoenix.Controller` behaviour (`success/4`, `failure/3`,
  `sign_out/2`), and `AshAuthentication.Phoenix.Controller` delegates `call/2`
  to a `Phoenix.Controller` pipeline, so the module must be a controller. It is
  declared with `formats: []`: no view module, no layout, no template, and no
  rendering of any kind. Every screen is a Blueprint route; this module only
  writes the session and redirects.

  User-visible messages are `Tunez.UI.Toast` rows keyed by the Blueprint
  session id, which survives the auth transition because it is UI state, not
  auth state.
  """

  use Phoenix.Controller, formats: []
  use AshAuthentication.Phoenix.Controller

  use TunezWeb, :verified_routes

  def success(conn, activity, user, _token) do
    message =
      case activity do
        {:confirm_new_user, :confirm} ->
          "Your email address has now been confirmed"

        {:password, :reset} ->
          "Your password has successfully been reset"

        {:password, :reset_request} ->
          "If this user exists in our system, you will receive password reset instructions shortly"

        {:magic_link, :request} ->
          "Check your email for a sign-in link"

        _ ->
          "You are now signed in"
      end

    return_to =
      case activity do
        {:password, :reset_request} -> ~p"/reset"
        {:magic_link, :request} -> ~p"/sign-in"
        _ -> get_session(conn, :return_to) || ~p"/"
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_session_toast(:info, message)
    |> redirect(to: return_to)
  end

  def failure(conn, activity, reason) do
    message =
      case {activity, reason} do
        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %Ash.Error.Forbidden{
             errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
           }
         }} ->
          """
          You have already signed in another way, but have not confirmed your account.
          You can confirm your account using the link we sent to you, or by resetting your password.
          """

        _ ->
          "Incorrect email or password"
      end

    conn
    |> put_session_toast(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"
    session_id = get_session(conn, "ash_blueprint_session_id")

    conn = clear_session(conn, :tunez)

    conn =
      if is_binary(session_id),
        do: put_session(conn, "ash_blueprint_session_id", session_id),
        else: conn

    conn
    |> put_session_toast(:info, "You are now signed out")
    |> redirect(to: return_to)
  end

  defp put_session_toast(conn, level, message) do
    case get_session(conn, "ash_blueprint_session_id") do
      session_id when is_binary(session_id) ->
        {:ok, _toast} = Tunez.UI.put_toast(session_id, level, message)
        conn

      _missing ->
        conn
    end
  end
end
