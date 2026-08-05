defmodule Tunez.UI do
  use Ash.Domain, otp_app: :tunez, extensions: [AshLua.Domain, AshAi]

  lua do
    namespace "ui.page_life" do
      action :read, Tunez.UI.PageLife, :read
      action :begin, Tunez.UI.PageLife, :begin
    end

    namespace "ui.app_shell" do
      action :for_session, Tunez.UI.AppShell, :for_session
      action :mount, Tunez.UI.AppShell, :mount
      action :toggle_menu, Tunez.UI.AppShell, :toggle_menu
      action :close_menu, Tunez.UI.AppShell, :close_menu
    end

    namespace "ui.page_header" do
      action :for_session, Tunez.UI.PageHeader, :for_session
      action :mount, Tunez.UI.PageHeader, :mount
      action :toggle_menu, Tunez.UI.PageHeader, :toggle_menu
      action :close_menu, Tunez.UI.PageHeader, :close_menu
    end

    namespace "ui.flash" do
      action :read, Tunez.UI.Flash, :read
      action :put, Tunez.UI.Flash, :put
      action :dismiss, Tunez.UI.Flash, :dismiss
    end

    namespace "ui.flash_stack" do
      action :for_session, Tunez.UI.FlashStack, :for_session
      action :mount, Tunez.UI.FlashStack, :mount
      action :dismiss, Tunez.UI.FlashStack, :dismiss
    end

    namespace "ui.artist_index_page" do
      action :for_session, Tunez.UI.ArtistIndexPage, :for_session
      action :mount, Tunez.UI.ArtistIndexPage, :mount
      action :search, Tunez.UI.ArtistIndexPage, :search
      action :set_query, Tunez.UI.ArtistIndexPage, :set_query
      action :change_sort, Tunez.UI.ArtistIndexPage, :change_sort
      action :previous_page, Tunez.UI.ArtistIndexPage, :previous_page
      action :next_page, Tunez.UI.ArtistIndexPage, :next_page
    end

    namespace "ui.artist_show_page" do
      action :for_session, Tunez.UI.ArtistShowPage, :for_session
      action :mount, Tunez.UI.ArtistShowPage, :mount
      action :follow_artist, Tunez.UI.ArtistShowPage, :follow_artist
      action :unfollow_artist, Tunez.UI.ArtistShowPage, :unfollow_artist
      action :destroy_album, Tunez.UI.ArtistShowPage, :destroy_album
      action :destroy_artist, Tunez.UI.ArtistShowPage, :destroy_artist
    end

    namespace "ui.artist_form_page" do
      action :for_session, Tunez.UI.ArtistFormPage, :for_session
      action :mount, Tunez.UI.ArtistFormPage, :mount
      action :edit, Tunez.UI.ArtistFormPage, :edit
      action :save, Tunez.UI.ArtistFormPage, :save
    end

    namespace "ui.album_form_page" do
      action :for_session, Tunez.UI.AlbumFormPage, :for_session
      action :mount, Tunez.UI.AlbumFormPage, :mount
      action :edit, Tunez.UI.AlbumFormPage, :edit
      action :add_track, Tunez.UI.AlbumFormPage, :add_track
      action :reorder_tracks, Tunez.UI.AlbumFormPage, :reorder_tracks
      action :save, Tunez.UI.AlbumFormPage, :save
    end

    namespace "ui.notifications_page" do
      action :for_session, Tunez.UI.NotificationsPage, :for_session
      action :mount, Tunez.UI.NotificationsPage, :mount
      action :toggle, Tunez.UI.NotificationsPage, :toggle
      action :close, Tunez.UI.NotificationsPage, :close
      action :dismiss, Tunez.UI.NotificationsPage, :dismiss
    end

    namespace "ui.confirm_page" do
      action :mount, Tunez.UI.ConfirmPage, :mount
    end

    namespace "ui.magic_sign_in_page" do
      action :mount, Tunez.UI.MagicSignInPage, :mount
    end

    namespace "ui.register_page" do
      action :mount, Tunez.UI.RegisterPage, :mount
      action :edit, Tunez.UI.RegisterPage, :edit
    end

    namespace "ui.reset_page" do
      action :mount, Tunez.UI.ResetPage, :mount
      action :edit, Tunez.UI.ResetPage, :edit
    end

    namespace "ui.sign_in_page" do
      action :mount, Tunez.UI.SignInPage, :mount
      action :edit, Tunez.UI.SignInPage, :edit
    end
  end

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
