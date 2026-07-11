defmodule Tunez.Music.Album do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.Music,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource, AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [AshBlueprint.Notifier]

  graphql do
    type :album
  end

  json_api do
    type "album"
    includes [:tracks]
  end

  postgres do
    table "albums"
    repo Tunez.Repo

    references do
      reference :artist, index?: true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :year_released, :cover_image_url, :artist_id]

      argument :tracks, {:array, Tunez.Music.TrackInput} do
        allow_nil? true
      end

      change fn changeset, _context ->
        manage_track_inputs(changeset)
      end
    end

    update :update do
      accept [:name, :year_released, :cover_image_url]
      require_atomic? false

      argument :tracks, {:array, Tunez.Music.TrackInput} do
        allow_nil? true
      end

      change fn changeset, _context ->
        manage_track_inputs(changeset)
      end
    end

    destroy :destroy do
      primary? true
      require_atomic? false

      change cascade_destroy(:notifications, return_notifications?: true, after_action?: false)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if actor_attribute_equals(:role, :editor)
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(can_manage_album?)
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  changes do
    change Tunez.Accounts.Changes.SendNewAlbumNotifications, on: [:create]

    change relate_actor(:created_by, allow_nil?: true), on: [:create]
    change relate_actor(:updated_by, allow_nil?: true)
  end

  validations do
    validate numericality(:year_released,
               greater_than: 1950,
               less_than_or_equal_to: Date.utc_today().year + 1
             ),
             where: [present(:year_released)],
             message: "must be between 1950 and next year"

    validate match(:cover_image_url, ~r"^(https://|/images/).+(\.png|\.jpg)$"),
      where: [changing(:cover_image_url)],
      message: "must start with https:// or /images/"
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :year_released, :integer do
      allow_nil? false
      public? true
    end

    attribute :cover_image_url, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :artist, Tunez.Music.Artist do
      allow_nil? false
    end

    has_many :tracks, Tunez.Music.Track do
      sort order: :asc
      public? true
    end

    has_many :notifications, Tunez.Accounts.Notification

    belongs_to :created_by, Tunez.Accounts.User
    belongs_to :updated_by, Tunez.Accounts.User
  end

  calculations do
    calculate :duration, :string, Tunez.Music.Calculations.SecondsToMinutes

    calculate :can_manage_album?,
              :boolean,
              expr(
                ^actor(:role) == :admin or
                  (^actor(:role) == :editor and created_by_id == ^actor(:id))
              )
  end

  aggregates do
    sum :duration_seconds, :tracks, :duration_seconds
  end

  identities do
    identity :unique_album_names_per_artist, [:name, :artist_id],
      message: "already exists for this artist"
  end

  defp manage_track_inputs(changeset) do
    case Ash.Changeset.get_argument(changeset, :tracks) do
      nil ->
        changeset

      tracks ->
        tracks =
          tracks
          |> Enum.with_index()
          |> Enum.map(fn {track, order} ->
            %{
              id: track.track_id,
              order: order,
              name: track.name,
              duration: track.duration
            }
          end)

        Ash.Changeset.manage_relationship(changeset, :tracks, tracks,
          type: :direct_control,
          order_is_key: :order
        )
    end
  end
end
