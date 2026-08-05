defmodule Tunez.Accounts.User.Senders.SendNewUserConfirmationEmail do
  @moduledoc """
  Sends an email for a new user to confirm their email address.
  """

  use AshAuthentication.Sender
  use TunezWeb, :verified_routes

  import Swoosh.Email

  alias Tunez.Mailer

  @impl true
  def send(user, token, _) do
    confirmation_url = url(~p"/confirm_new_user/#{token}")

    new()
    # TODO: Replace with your email
    |> from({"noreply", "noreply@example.com"})
    |> to(to_string(user.email))
    |> subject("Confirm your email address")
    |> html_body("""
    <p>Click this link to confirm your email:</p>
    <p><a href="#{confirmation_url}">#{confirmation_url}</a></p>
    """)
    |> Mailer.deliver!()
  end
end
