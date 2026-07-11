defmodule Tunez.UI do
  use Ash.Domain, otp_app: :tunez

  resources do
    resource Tunez.UI.AlbumFormPage do
      define :initialize_album_tracks, action: :initialize_tracks, args: [:tracks]
    end

    resource Tunez.UI.ArtistFormPage
    resource Tunez.UI.ArtistIndexPage
    resource Tunez.UI.ArtistShowPage

    resource Tunez.UI.FlashStack do
      define :put_flash,
        action: :put_flash,
        args: [:session_id, :level, :message],
        default_options: [upsert?: true, upsert_identity: :session_instance]
    end

    resource Tunez.UI.NotificationsPage
    resource Tunez.UI.AppShell
    resource Tunez.UI.PageHeader
  end
end
