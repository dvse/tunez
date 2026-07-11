defmodule Tunez.Music.Artist do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.Music,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource, AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [AshBlueprint.Notifier]

  graphql do
    type :artist

    filterable_fields [
      :album_count,
      :cover_image_url,
      :inserted_at,
      :latest_album_year_released,
      :updated_at
    ]
  end

  json_api do
    type "artist"
    includes albums: [:tracks]
    derive_filter? false
  end

  postgres do
    table "artists"
    repo Tunez.Repo

    custom_indexes do
      index "name gin_trgm_ops", name: "artists_name_gin_index", using: "GIN"
    end
  end

  resource do
    description "A person or group of people that makes and releases music."
  end

  actions do
    defaults [:read]

    read :search do
      description "List Artists, optionally filtering by name."

      argument :query, :ci_string do
        description "Return only artists with names including the given value."
        constraints allow_empty?: true
        default ""
        public? true
      end

      filter expr(contains(name, ^arg(:query)))

      pagination offset?: true, default_limit: 12
    end

    read :browse do
      description "Read one typed catalogue page for an Ash UI relationship."

      argument :query, :ci_string do
        allow_nil? false
        default ""
        constraints allow_empty?: true
      end

      argument :sort_by, :atom do
        allow_nil? false

        constraints one_of: [
                      :"-updated_at",
                      :"-inserted_at",
                      :name,
                      :"-album_count",
                      :"--latest_album_year_released",
                      :"-follower_count",
                      :"-followed_by_me"
                    ]
      end

      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 48]
      argument :offset, :integer, allow_nil?: false, constraints: [min: 0]

      filter expr(contains(name, ^arg(:query)))

      prepare fn query, _context ->
        sort =
          case Ash.Query.get_argument(query, :sort_by) do
            :"-inserted_at" ->
              [inserted_at: :desc]

            :name ->
              [name: :asc]

            :"-album_count" ->
              [album_count: :desc, name: :asc]

            :"--latest_album_year_released" ->
              [latest_album_year_released: :desc_nils_last, name: :asc]

            :"-follower_count" ->
              [follower_count: :desc, name: :asc]

            :"-followed_by_me" ->
              [followed_by_me: :desc, name: :asc]

            :"-updated_at" ->
              [updated_at: :desc]
          end

        query
        |> Ash.Query.sort(sort)
        |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
        |> Ash.Query.offset(Ash.Query.get_argument(query, :offset))
      end
    end

    create :create do
      accept [:name, :biography]
    end

    update :update do
      accept [:name, :biography]
      require_atomic? false
      change Tunez.Music.Changes.UpdatePreviousNames
    end

    destroy :destroy do
      primary? true
      require_atomic? false

      change cascade_destroy(:albums,
               return_notifications?: true,
               after_action?: false
             )
    end
  end

  policies do
    policy action(:create) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :editor)
    end

    policy action(:destroy) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  changes do
    change relate_actor(:created_by, allow_nil?: true), on: [:create]
    change relate_actor(:updated_by, allow_nil?: true)
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :biography, :string do
      public? true
    end

    attribute :previous_names, {:array, :string} do
      default []
      public? true
    end

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    has_many :albums, Tunez.Music.Album do
      sort year_released: :desc
      public? true
    end

    has_many :follower_relationships, Tunez.Music.ArtistFollower

    many_to_many :followers, Tunez.Accounts.User do
      join_relationship :follower_relationships
      destination_attribute_on_join_resource :follower_id
    end

    belongs_to :created_by, Tunez.Accounts.User
    belongs_to :updated_by, Tunez.Accounts.User
  end

  calculations do
    calculate :followed_by_me,
              :boolean,
              expr(exists(follower_relationships, follower_id == ^actor(:id))) do
      public? true
    end
  end

  aggregates do
    count :album_count, :albums do
      public? true
    end

    first :latest_album_year_released, :albums, :year_released do
      public? true
    end

    first :cover_image_url, :albums, :cover_image_url do
      public? true
    end

    count :follower_count, :follower_relationships do
      public? true
    end
  end
end
