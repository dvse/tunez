defmodule Tunez.Music.Artist do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.Music,
    notifiers: [AshBlueprint.Notifier],
    data_layer: AshPostgres.DataLayer,
    extensions: [AshGraphql.Resource, AshJsonApi.Resource, AshLua.Resource],
    authorizers: [Ash.Policy.Authorizer]

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

    policy action([:follow, :unfollow]) do
      authorize_if actor_present()
    end

    policy action(:destroy) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
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

  changes do
    change relate_actor(:created_by, allow_nil?: true), on: [:create]
    change relate_actor(:updated_by, allow_nil?: true)
  end

  actions do
    defaults [:read]

    read :search do
      description "List Artists, optionally filtering by name."

      argument :query, :ci_string do
        description "Return only artists with names including the given value."
        constraints allow_empty?: true
        default ""
      end

      filter expr(contains(name, ^arg(:query)))

      pagination offset?: true, default_limit: 12
    end

    read :browse do
      description "Catalogue window: name search, sort, and paging as one typed read."

      argument :query, :ci_string do
        constraints allow_empty?: true
        default ""
      end

      argument :sort_by, :string do
        default "name"
      end

      argument :limit, :integer do
        default 12
        constraints min: 1, max: 100
      end

      argument :offset, :integer do
        default 0
        constraints min: 0
      end

      filter expr(contains(name, ^arg(:query)))

      prepare fn query, _context ->
        query
        |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
        |> Ash.Query.offset(Ash.Query.get_argument(query, :offset))
        |> Ash.Query.sort_input(Ash.Query.get_argument(query, :sort_by))
      end
    end

    create :create do
      accept [:name, :biography]
    end

    update :update do
      accept [:name, :biography]

      change atomic_update(
               :previous_names,
               expr(
                 fragment(
                   "array_remove(array_prepend(?, ?), ?)",
                   name,
                   previous_names,
                   ^atomic_ref(:name)
                 )
               ),
               cast_atomic?: false
             )
    end

    update :follow do
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          case Tunez.Music.follow_artist(changeset.data, scope: context) do
            {:ok, _follow} ->
              changeset

            {:error, error} ->
              Ash.Changeset.add_error(changeset, [
                Ash.Error.Changes.InvalidChanges.exception(message: "Could not follow artist"),
                error
              ])
          end
        end)
      end
    end

    update :unfollow do
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          case Tunez.Music.unfollow_artist(changeset.data, scope: context) do
            :ok ->
              changeset

            {:error, error} ->
              Ash.Changeset.add_error(changeset, [
                Ash.Error.Changes.InvalidChanges.exception(message: "Could not unfollow artist"),
                error
              ])
          end
        end)
      end
    end

    destroy :destroy do
      primary? true

      change cascade_destroy(:albums,
               return_notifications?: true,
               after_action?: false
             )
    end
  end
end
