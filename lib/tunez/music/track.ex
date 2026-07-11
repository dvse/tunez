defmodule Tunez.Music.Track do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.Music,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource],
    notifiers: [AshBlueprint.Notifier]

  graphql do
    type :track
  end

  json_api do
    type "track"
    default_fields [:number, :name, :duration_seconds]
  end

  postgres do
    table "tracks"
    repo Tunez.Repo

    references do
      reference :album, index?: true, on_delete: :delete
    end
  end

  policies do
    policy always() do
      authorize_if accessing_from(Tunez.Music.Album, :tracks)
      authorize_if action_type(:read)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :order, :integer do
      allow_nil? false
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :duration_seconds, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :album, Tunez.Music.Album do
      allow_nil? false
    end
  end

  calculations do
    calculate :duration, :string, Tunez.Music.Calculations.SecondsToMinutes do
      public? true
    end

    calculate :number, :integer, expr(order + 1) do
      public? true
    end
  end

  preparations do
    prepare build(load: [:number])
  end

  actions do
    defaults [:read]

    destroy :destroy do
      primary? true
      require_atomic? false
    end

    create :create do
      primary? true
      accept [:order, :name, :album_id]
      argument :duration, :string, allow_nil?: false
      validate match(:duration, ~r/^\d+:\d{2}$/), message: "use MM:SS format"

      validate argument_does_not_equal(:duration, "0:00"),
        message: "must be at least 1 second long"

      validate argument_does_not_equal(:duration, "00:00"),
        message: "must be at least 1 second long"

      change fn changeset, _context ->
               [minutes, seconds] =
                 changeset |> Ash.Changeset.get_argument(:duration) |> String.split(":", parts: 2)

               Ash.Changeset.change_attribute(
                 changeset,
                 :duration_seconds,
                 String.to_integer(minutes) * 60 + String.to_integer(seconds)
               )
             end,
             only_when_valid?: true
    end

    update :update do
      primary? true
      accept [:order, :name]
      require_atomic? false
      argument :duration, :string, allow_nil?: false
      validate match(:duration, ~r/^\d+:\d{2}$/), message: "use MM:SS format"

      validate argument_does_not_equal(:duration, "0:00"),
        message: "must be at least 1 second long"

      validate argument_does_not_equal(:duration, "00:00"),
        message: "must be at least 1 second long"

      change fn changeset, _context ->
               [minutes, seconds] =
                 changeset |> Ash.Changeset.get_argument(:duration) |> String.split(":", parts: 2)

               Ash.Changeset.change_attribute(
                 changeset,
                 :duration_seconds,
                 String.to_integer(minutes) * 60 + String.to_integer(seconds)
               )
             end,
             only_when_valid?: true
    end
  end
end
