defmodule TunezWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use TunezWeb, :verified_routes

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {TunezWeb.LiveUserAuth, :current_user}
  # Host-boundary flash handoff: auth/controller flows write Phoenix
  # flash; the UI renders in-model FlashStack rows. Normalize at mount and
  # clear the transport copy.
  def on_mount(:blueprint_flash, _params, session, socket) do
    session_id = session["ash_blueprint_session_id"]

    if is_binary(session_id) do
      socket.assigns
      |> Map.get(:flash, %{})
      |> Enum.each(fn
        {kind, message} when kind in ["info", "error", "warning"] and is_binary(message) ->
          Tunez.UI.put_flash(session_id, String.to_existing_atom(kind), message,
            authorize?: false
          )

        _other ->
          :ok
      end)
    end

    {:cont, Phoenix.LiveView.clear_flash(socket)}
  end

  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount([role_required: role_required], _, _, socket) do
    current_user = socket.assigns[:current_user]

    if current_user && current_user.role == role_required do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "Unauthorized!")
        |> Phoenix.LiveView.redirect(to: "/")

      {:halt, socket}
    end
  end
end
