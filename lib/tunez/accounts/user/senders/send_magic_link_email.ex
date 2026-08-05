defmodule Tunez.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a magic link email
  """

  use AshAuthentication.Sender
  use TunezWeb, :verified_routes

  import Swoosh.Email
  alias Tunez.Mailer

  @impl true
  def send(user_or_email, token, _) do
    # if you get a user, its for a user that already exists.
    # if you get an email, then the user does not yet exist.

    email =
      case user_or_email do
        %{email: email} -> email
        email -> email
      end

    sign_in_url = url(~p"/magic_link/#{token}")

    new()
    # TODO: Replace with your email
    |> from({"noreply", "noreply@example.com"})
    |> to(to_string(email))
    |> subject("Your login link")
    |> html_body("""
    <p>Hello, #{email}! Click this link to sign in:</p>
    <p><a href="#{sign_in_url}">#{sign_in_url}</a></p>
    """)
    |> Mailer.deliver!()
  end
end
