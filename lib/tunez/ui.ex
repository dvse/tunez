defmodule Tunez.UI do
  use Ash.Domain, otp_app: :tunez

  resources do
    resource Tunez.UI.AlbumFormPage
    resource Tunez.UI.ArtistFormPage

    resource Tunez.UI.ArtistIndexPage
    resource Tunez.UI.ArtistShowPage
    resource Tunez.UI.ConfirmPage

    resource Tunez.UI.FlashStack

    resource Tunez.UI.Flash do
      define :put_flash, action: :put, args: [:session_id, :kind, :message]
      define :dismiss_flash, action: :dismiss, get_by_identity: :session_kind
    end

    resource Tunez.UI.PageLife do
      define :begin_page_life, action: :begin, args: [:session_id]
      define :current_page_life, action: :read, get_by: :session_id
    end

    resource Tunez.UI.NotificationsPage
    resource Tunez.UI.MagicSignInPage
    resource Tunez.UI.RegisterPage
    resource Tunez.UI.ResetPage
    resource Tunez.UI.SignInPage
    resource Tunez.UI.AppShell
    resource Tunez.UI.PageHeader
  end
end
