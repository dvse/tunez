defmodule Tunez.MCP.Actions do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.MCP,
    data_layer: Ash.DataLayer.Simple,
    extensions: [AshLua.Resource, AshLua.EvalActions],
    authorizers: [Ash.Policy.Authorizer]

  eval_actions do
    resource Tunez.Accounts.Notification
    resource Tunez.Music.Artist
    resource Tunez.Music.Album
    resource Tunez.Music.Track
    resource Tunez.Music.ArtistFollower
    resource Tunez.UI.AppShell
    resource Tunez.UI.PageHeader
    resource Tunez.UI.Toast
    resource Tunez.UI.ToastStack
    resource Tunez.UI.ArtistIndexPage
    resource Tunez.UI.ArtistShowPage
    resource Tunez.UI.ArtistFormPage
    resource Tunez.UI.AlbumFormPage
    resource Tunez.UI.NotificationsPage
    resource Tunez.UI.ConfirmPage
    resource Tunez.UI.MagicSignInPage
    resource Tunez.UI.RegisterPage
    resource Tunez.UI.ResetPage
    resource Tunez.UI.SignInPage
  end

  resource do
    require_primary_key? false

    description """
    The Tunez automation boundary. Accounts, Music, and UI own their public Lua action
    declarations; this resource limits synthesized documentation and evaluation to the listed
    resources. MCP publishes only those two synthesized actions.
    """
  end

  policies do
    policy action([:docs, :eval]) do
      authorize_if always()
    end
  end
end
