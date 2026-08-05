defmodule Tunez.Accounts.Notification do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshLua.Resource],
    notifiers: [AshBlueprint.Notifier, Ash.Notifier.PubSub]

  postgres do
    table "notifications"
    repo Tunez.Repo

    references do
      reference :user, index?: true, on_delete: :delete
      reference :album
    end
  end

  policies do
    bypass AshQueue.Checks.AshQueueInteraction do
      authorize_if always()
    end

    policy action(:read) do
      authorize_if expr(
                     ^actor(:role) == :admin or
                       (^actor(:role) == :editor and album.created_by_id == ^actor(:id))
                   )
    end

    policy action(:create) do
      forbid_if always()
    end

    policy action(:create_for_album_release) do
      forbid_if always()
    end

    policy action(:for_user) do
      authorize_if actor_present()
    end

    policy action(:destroy) do
      authorize_if expr(
                     ^actor(:role) == :admin or
                       (^actor(:role) == :editor and album.created_by_id == ^actor(:id))
                   )

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

  identities do
    identity :one_per_album_follower, [:album_id, :user_id]
  end

  pub_sub do
    prefix "notifications"
    module TunezWeb.Endpoint

    transform fn notification ->
      Map.take(notification.data, [:id, :user_id, :album_id])
    end

    publish :create, [:user_id]
    publish :create_for_album_release, [:user_id]
    publish :destroy, [:user_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:user_id, :album_id]
    end

    create :create_for_album_release do
      public? false
      accept [:user_id, :album_id]
      upsert? true
      upsert_identity :one_per_album_follower
      upsert_fields []
    end

    read :for_user do
      prepare build(load: [album: [:artist]], sort: [inserted_at: :desc])
      filter expr(user_id == ^actor(:id))
    end
  end
end
