defmodule Tunez.Music.TrackInput do
  use Ash.Resource,
    otp_app: :tunez,
    data_layer: :embedded,
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy action([:create, :update, :destroy]) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :track_id, :uuid do
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      default ""
      public? true
      constraints allow_empty?: true
    end

    attribute :duration, :string do
      allow_nil? false
      default ""
      public? true
      constraints allow_empty?: true
    end
  end

  actions do
    create :create do
      primary? true
      accept [:track_id, :name, :duration]
    end

    update :update do
      primary? true
      accept [:track_id, :name, :duration]
    end

    destroy :destroy do
      primary? true
    end
  end
end
