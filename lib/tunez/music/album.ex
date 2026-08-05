defmodule Tunez.Music.Album do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.Music,
    notifiers: [AshBlueprint.Notifier],
    data_layer: AshPostgres.DataLayer,
    extensions: [AshQueue.Resource, AshGraphql.Resource, AshJsonApi.Resource, AshLua.Resource],
    authorizers: [Ash.Policy.Authorizer]

  graphql do
    type :album
  end

  queue do
    domain Tunez.Music
    # Tunez has no multitenancy. Queue reads and jobs are domain-global.
    use_tenant_from_record?(false)

    transition :fan_out_album_release_notifications do
      queue :album_notifications
      actor_persister Tunez.QueueActorPersister
      max_attempts 3
      backoff :exponential
      consumes_match?(true)

      where expr(
              exists(
                Tunez.Music.ArtistFollower,
                artist_id == parent(artist_id) and
                  not exists(
                    Tunez.Accounts.Notification,
                    album_id == parent(parent(id)) and user_id == parent(follower_id)
                  )
              )
            )
    end
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

  policies do
    bypass AshQueue.Checks.AshQueueInteraction do
      authorize_if always()
    end

    policy action(:manageable) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(^actor(:role) == :editor and created_by_id == ^actor(:id))
    end

    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if actor_attribute_equals(:role, :editor)
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(
                     ^actor(:role) == :admin or
                       (^actor(:role) == :editor and created_by_id == ^actor(:id))
                   )
    end

    policy action_type(:read) do
      authorize_if always()
    end
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

  aggregates do
    sum :duration_seconds, :tracks, :duration_seconds do
      public? true
    end
  end

  identities do
    identity :unique_album_names_per_artist, [:name, :artist_id],
      message: "already exists for this artist"
  end

  changes do
    change relate_actor(:created_by, allow_nil?: true), on: [:create]
    change relate_actor(:updated_by, allow_nil?: true)
  end

  validations do
    validate fn changeset, _context ->
               year_released = Ash.Changeset.get_attribute(changeset, :year_released)

               if year_released > 1950 and year_released <= Date.utc_today().year + 1 do
                 :ok
               else
                 {:error, field: :year_released, message: "must be between 1950 and next year"}
               end
             end,
             where: [present(:year_released)]

    validate match(:cover_image_url, ~r"^(https://|/images/).+(\.png|\.jpg)$"),
      where: [changing(:cover_image_url)],
      message: "must start with https:// or /images/"
  end

  actions do
    read :manageable do
      public? false
      prepare build(load: [:tracks])
    end

    defaults [:read]

    create :create do
      accept [:name, :year_released, :cover_image_url, :artist_id]

      argument :tracks, {:array, :map} do
        constraints items: [
                      fields: [
                        id: [type: :uuid],
                        order: [type: :integer, constraints: [min: 0]],
                        name: [type: :string, allow_nil?: false],
                        duration: [type: :string, allow_nil?: false]
                      ]
                    ]
      end

      change manage_relationship(:tracks, type: :direct_control, order_is_key: :order)
    end

    update :fan_out_album_release_notifications do
      public? false
      accept []
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          inputs =
            changeset.data.artist_id
            |> Tunez.Music.missing_notification_followers_for_album!(
              changeset.data.id,
              scope: context
            )
            |> Enum.map(fn follower ->
              %{album_id: changeset.data.id, user_id: follower.follower_id}
            end)

          case Ash.bulk_create(
                 inputs,
                 Tunez.Accounts.Notification,
                 :create_for_album_release,
                 domain: Tunez.Accounts,
                 scope: context,
                 context: context.source_context,
                 authorize?: true,
                 transaction: false,
                 notify?: true,
                 return_errors?: true,
                 stop_on_error?: true
               ) do
            %Ash.BulkResult{status: :success} ->
              changeset

            %Ash.BulkResult{errors: [error | _errors]} ->
              Ash.Changeset.add_error(changeset, error)

            result ->
              Ash.Changeset.add_error(
                changeset,
                "notification fan-out failed: #{inspect(result)}"
              )
          end
        end)
      end
    end

    update :update do
      accept [:name, :year_released, :cover_image_url]
      require_atomic? false

      argument :tracks, {:array, :map} do
        constraints items: [
                      fields: [
                        id: [type: :uuid],
                        order: [type: :integer, constraints: [min: 0]],
                        name: [type: :string, allow_nil?: false],
                        duration: [type: :string, allow_nil?: false]
                      ]
                    ]
      end

      change manage_relationship(:tracks, type: :direct_control, order_is_key: :order)
    end

    update :upload_cover do
      description "Upload a local image file and use the stored image as this album's cover."
      accept []
      require_atomic? false

      argument :path, :string do
        allow_nil? false
        public? true
        constraints allow_empty?: false
        description "Absolute path to a PNG or JPEG under a server-configured MCP upload root."
      end

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          source_path = Ash.Changeset.get_argument(changeset, :path) |> Path.expand()

          allowed_root =
            :tunez
            |> Application.get_env(:mcp_upload_roots, [])
            |> Enum.map(&Path.expand/1)
            |> Enum.find(fn root ->
              source_path == root or String.starts_with?(source_path, root <> "/")
            end)

          path_check =
            if allowed_root do
              source_path
              |> Path.relative_to(allowed_root)
              |> Path.split()
              |> Enum.reduce_while({:ok, allowed_root}, fn component, {:ok, parent} ->
                candidate = Path.join(parent, component)

                case File.lstat(candidate) do
                  {:ok, %{type: :symlink}} -> {:halt, {:error, :symlink}}
                  {:ok, _stat} -> {:cont, {:ok, candidate}}
                  {:error, reason} -> {:halt, {:error, reason}}
                end
              end)
            else
              {:error, :outside_allowed_roots}
            end

          with {:ok, ^source_path} <- path_check,
               {:ok, %{type: :regular, size: size}} when size <= 10_000_000 <-
                 File.stat(source_path),
               {:ok, content} <- File.read(source_path),
               {:ok, format} <-
                 (case content do
                    <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> -> {:ok, :png}
                    <<255, 216, 255, _rest::binary>> -> {:ok, :jpg}
                    _content -> {:error, :invalid_image}
                  end),
               filename =
                 Base.encode16(:crypto.hash(:sha256, content), case: :lower) <> ".#{format}",
               directory = Application.app_dir(:tunez, "priv/static/images/uploads"),
               destination = Path.join(directory, filename),
               :ok <- File.mkdir_p(directory),
               result when result in [:ok, {:error, :eexist}] <-
                 File.write(destination, content, [:binary, :exclusive]) do
            Ash.Changeset.force_change_attribute(
              changeset,
              :cover_image_url,
              "/images/uploads/#{filename}"
            )
          else
            {:error, :outside_allowed_roots} ->
              Ash.Changeset.add_error(changeset,
                field: :path,
                message: "is outside the configured MCP upload roots"
              )

            {:error, :symlink} ->
              Ash.Changeset.add_error(changeset,
                field: :path,
                message: "must not contain symbolic links"
              )

            {:ok, %{size: size}} when size > 10_000_000 ->
              Ash.Changeset.add_error(changeset,
                field: :path,
                message: "must be no larger than 10000000 bytes"
              )

            {:ok, %{type: type}} ->
              Ash.Changeset.add_error(changeset,
                field: :path,
                message: "must be a regular file, got #{type}"
              )

            {:error, :invalid_image} ->
              Ash.Changeset.add_error(changeset,
                field: :path,
                message: "must contain a PNG or JPEG image"
              )

            {:error, reason} ->
              Ash.Changeset.add_error(changeset,
                field: :path,
                message: "could not store cover: #{:file.format_error(reason)}"
              )
          end
        end)
      end
    end

    destroy :destroy do
      primary? true

      change cascade_destroy(:notifications, return_notifications?: true, after_action?: false)
    end
  end
end
