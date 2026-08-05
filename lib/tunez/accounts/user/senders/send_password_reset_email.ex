defmodule Tunez.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Sends a password reset email
  """

  use AshAuthentication.Sender
  use TunezWeb, :verified_routes

  import Swoosh.Email

  alias Tunez.Mailer

  @impl true
  def send(user, token, _) do
    reset_url = url(~p"/password-reset/#{token}")

    new()
    # TODO: Replace with your email
    |> from({"noreply", "noreply@example.com"})
    |> to(to_string(user.email))
    |> subject("Reset your password")
    |> html_body("""
    <p>Click this link to reset your password:</p>
    <p><a href="#{reset_url}">#{reset_url}</a></p>
    """)
    |> Mailer.deliver!()
  end
end
