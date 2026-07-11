defmodule TunezWeb.AuthController do
  use TunezWeb, :controller
  use AshAuthentication.Phoenix.Controller

  # Flash is the Tunez.UI.FlashStack RESOURCE, keyed by the blueprint
  # session id — no Phoenix flash affordances. The id survives auth
  # transitions (it is UI session state, not auth state).

  def success(conn, activity, user, _token) do
    return_to = get_session(conn, :return_to) || "/"

    message =
      case activity do
        {:confirm_new_user, :confirm} -> "Your email address has now been confirmed"
        {:password, :reset} -> "Your password has successfully been reset"
        _ -> "You are now signed in"
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_session_flash(:info, message)
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
    |> put_session_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || "/"
    session_id = get_session(conn, "ash_blueprint_session_id")

    conn = clear_session(conn, :tunez)

    conn =
      if is_binary(session_id),
        do: put_session(conn, "ash_blueprint_session_id", session_id),
        else: conn

    conn
    |> put_session_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end

  defp put_session_flash(conn, level, message) do
    case get_session(conn, "ash_blueprint_session_id") do
      session_id when is_binary(session_id) ->
        {:ok, _flash} = Tunez.UI.put_flash(session_id, level, message, authorize?: false)
        conn

      _missing ->
        conn
    end
  end
end
