defmodule Tunez.Accounts.Notification do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [AshBlueprint.Notifier]

  postgres do
    table "notifications"
    repo Tunez.Repo

    references do
      reference :user, index?: true, on_delete: :delete
      reference :album
    end
  end

  policies do
    policy action(:read) do
      authorize_if expr(album.can_manage_album?)
    end

    policy action(:create) do
      forbid_if always()
    end

    policy action(:notify_album_followers) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :editor)
    end

    policy action(:for_user) do
      authorize_if actor_present()
    end

    policy action(:destroy) do
      authorize_if expr(album.can_manage_album?)
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :user, Tunez.Accounts.User do
      allow_nil? false
    end

    belongs_to :album, Tunez.Music.Album do
      allow_nil? false
    end
  end

  actions do
    defaults [:read]

    destroy :destroy do
      primary? true
      require_atomic? false
    end

    create :create do
      accept [:user_id, :album_id]
    end

    action :notify_album_followers do
      argument :album, :struct do
        allow_nil? false
        constraints instance_of: Tunez.Music.Album
      end

      run fn input, context ->
        album = input.arguments.album

        album.artist_id
        |> Tunez.Music.followers_for_artist!(scope: context, stream?: true)
        |> Stream.map(&%{album_id: album.id, user_id: &1.follower_id})
        |> Ash.bulk_create!(Tunez.Accounts.Notification, :create,
          authorize?: false,
          notify?: true
        )

        :ok
      end
    end

    read :for_user do
      prepare build(load: [album: [:artist]], sort: [inserted_at: :desc])
      filter expr(user_id == ^actor(:id))
    end
  end
end
