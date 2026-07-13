defmodule Tunez.UI.AlbumFormPage do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint, AshLua.Resource],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  routes do
    route "/artists/:artist_id/albums/new" do
      location(expr(if(not is_nil(saved_artist_id), do: "/artists/" <> saved_artist_id)))
      param(:artist_id, :uuid)
    end

    route "/albums/:album_id/edit" do
      param(:album_id, :uuid)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy always() do
      authorize_if actor_attribute_equals(:role, :editor)
    end
  end

  attributes do
    attribute :session_id, :uuid, allow_nil?: false, primary_key?: true, public?: false
    attribute :subject_id, :string, allow_nil?: false, primary_key?: true, public?: false
    attribute :artist_id, :uuid, public?: true
    attribute :saved_artist_id, :string, public?: true
    attribute :album_id, :uuid, public?: true

    attribute :name, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [allow_empty?: true]

    attribute :year_released, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [allow_empty?: true]

    attribute :cover_image_url, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [allow_empty?: true]

    attribute :tracks, {:array, Tunez.UI.AlbumTrackRow},
      allow_nil?: false,
      default: [],
      public?: true,
      description:
        "Nested album-track rows. Updates identify an existing row by id and pass its editable name and duration fields."
  end

  relationships do
    has_one :app_shell, Tunez.UI.AppShell,
      source_attribute: :session_id,
      destination_attribute: :session_id

    has_many :page_headers, Tunez.UI.PageHeader,
      source_attribute: :session_id,
      destination_attribute: :session_id

    has_one :artist, Tunez.Music.Artist do
      source_attribute :artist_id
      destination_attribute :id
      public? true
    end

    belongs_to :album, Tunez.Music.Album do
      define_attribute? false
      source_attribute :album_id
      read_action :manageable
      public? true
    end
  end

  calculations do
    calculate :page_title,
              :string,
              expr(if(is_nil(album_id), do: "New Album", else: "Update Album")),
              public?: true

    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                render(Tunez.UI.AppShell, %{
                  signed_in?: true,
                  email: to_string(^actor(:email)),
                  content: [
                    render(Tunez.UI.PageHeader, %{
                      kind: :simple,
                      title:
                        heading(:page_h1, [level: 1], [
                          text(if(is_nil(album_id), do: "New Album", else: "Update Album"))
                        ])
                    }),
                    form(
                      :album_form,
                      [
                        dom_id: "album_form",
                        on_submit: :save
                      ],
                      [
                        box(:form_stack, [], [
                          render(Tunez.UI.FormControl, %{
                            label: "Artist",
                            control:
                              input(
                                :form_input,
                                [
                                  value: coalesce(album.artist.name, artist.name),
                                  disabled: true
                                ],
                                []
                              )
                          }),
                          box(:album_fields_row, [], [
                            box(:album_name_field, [], [
                              render(Tunez.UI.FormControl, %{
                                label: "Name",
                                dom_id: "album_form_name",
                                control:
                                  input(
                                    :form_input,
                                    [
                                      dom_id: "album_form_name",
                                      name: "name",
                                      value: coalesce(name, ""),
                                      on_input: :edit
                                    ],
                                    []
                                  ),
                                error: join(field_errors(:name), ", ")
                              })
                            ]),
                            box(:album_year_field, [], [
                              render(Tunez.UI.FormControl, %{
                                label: "Year Released",
                                dom_id: "album_form_year_released",
                                control:
                                  input(
                                    :form_input,
                                    [
                                      type: :number,
                                      dom_id: "album_form_year_released",
                                      name: "year_released",
                                      value: coalesce(year_released, ""),
                                      on_input: :edit
                                    ],
                                    []
                                  ),
                                error: join(field_errors(:year_released), ", ")
                              })
                            ])
                          ]),
                          render(Tunez.UI.FormControl, %{
                            label: "Cover Image URL",
                            dom_id: "album_form_cover_image_url",
                            control:
                              input(
                                :form_input,
                                [
                                  dom_id: "album_form_cover_image_url",
                                  name: "cover_image_url",
                                  value: coalesce(cover_image_url, ""),
                                  on_input: :edit
                                ],
                                []
                              ),
                            error: join(field_errors(:cover_image_url), ", ")
                          }),
                          heading(:page_h2, [level: 2], [text("Tracks")]),
                          table(:track_editor_table, [], [
                            table_head(:track_editor_head, [], [
                              row(:track_editor_header_row, [], [
                                header_cell(:track_editor_order_header, [], []),
                                header_cell(:track_editor_header, [], [text("Name")]),
                                header_cell(:track_editor_header, [colspan: 2], [
                                  text("Duration")
                                ])
                              ])
                            ]),
                            table_body(
                              :track_editor_body,
                              [
                                dom_id: "trackSort",
                                client_driver: :track_sort,
                                on_reorder: :reorder_tracks,
                                action_input: %{order: event(:order)}
                              ],
                              [
                                each(tracks, :track, [key: track.id], [
                                  render(Tunez.UI.AlbumTrackRow, track)
                                ])
                              ]
                            )
                          ]),
                          link(
                            :primary_link_inverse_small,
                            [to: "#", on_click: :add_track, prevent_default: true],
                            [text("Add Track")]
                          ),
                          box(:form_actions, [], [button(:form_button, [], [text("Save")])])
                        ])
                      ]
                    )
                  ]
                })
              )
  end

  identities do
    identity :session_instance, [:session_id, :subject_id], pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    read :for_session do
      description "Read album form and nested track-row UI state for one browser session."

      argument :session_id, :uuid do
        allow_nil? false
        public? true
      end

      filter expr(session_id == ^arg(:session_id))
    end

    create :mount do
      # Static and connected mounts share one row. Conflict updates leave
      # editable attributes untouched, preserving in-progress input.
      upsert? true
      upsert_identity :session_instance
      upsert_fields [:artist_id, :album_id, :saved_artist_id]

      argument :artist_id, :uuid
      argument :album_id, :uuid
      validate present([:artist_id, :album_id], exactly: 1)
      change AshBlueprint.Changes.SetSessionId
      change Tunez.UI.Changes.BeginPageLife
      change set_attribute(:artist_id, arg(:artist_id))

      change fn changeset, _context ->
        subject_id =
          case Ash.Changeset.get_argument(changeset, :artist_id) do
            nil -> "album:" <> Ash.Changeset.get_argument(changeset, :album_id)
            artist_id -> "artist:" <> artist_id
          end

        Ash.Changeset.change_attribute(changeset, :subject_id, subject_id)
      end

      change manage_relationship(:album_id, :album,
               type: :append,
               on_lookup: {:relate, :edit, :manageable}
             )

      change set_attribute(:saved_artist_id, nil)

      change fn changeset, context ->
        if Ash.Changeset.get_argument(changeset, :album_id) do
          Ash.Changeset.before_action(changeset, fn changeset ->
            with {:ok, page} <- Ash.Changeset.apply_attributes(changeset),
                 {:ok, %{album: %Tunez.Music.Album{} = album}} <-
                   Ash.load(page, [album: [tracks: [:duration]]], scope: context) do
              Ash.Changeset.force_change_attributes(changeset, %{
                name: album.name,
                year_released: to_string(album.year_released),
                cover_image_url: album.cover_image_url || "",
                tracks: track_rows(album.tracks)
              })
            else
              {:error, error} ->
                error
                |> Ash.Error.to_error_class()
                |> Map.fetch!(:errors)
                |> then(&Ash.Changeset.add_error(changeset, &1))

              _missing_album ->
                changeset
            end
          end)
        else
          changeset
        end
      end
    end

    update :store_tracks do
      primary? true
      public? false
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          tracks =
            changeset
            |> Ash.Changeset.get_attribute(:tracks)
            |> Enum.with_index()
            |> Enum.map(fn {track, position} -> %{track | position: position} end)

          Ash.Changeset.force_change_attribute(changeset, :tracks, tracks)
        end)
      end
    end

    update :edit do
      accept [:name, :year_released, :cover_image_url, :tracks]
    end

    update :add_track do
      require_atomic? false

      change fn changeset, _context ->
        tracks = changeset.data.tracks
        tracks = tracks ++ [%{position: length(tracks)}]
        Ash.Changeset.change_attribute(changeset, :tracks, tracks)
      end
    end

    update :reorder_tracks do
      require_atomic? false

      argument :order, {:array, :integer},
        allow_nil?: false,
        public?: true,
        constraints: [items: [min: 0]]

      validate fn changeset, _context ->
        order = Ash.Changeset.get_argument(changeset, :order)

        expected = Enum.to_list(0..(length(changeset.data.tracks) - 1)//1)

        if is_list(order) and Enum.sort(order) == expected do
          :ok
        else
          {:error,
           field: :order, message: "must be an exact permutation of the current track indices"}
        end
      end

      change fn changeset, _context ->
               tracks = changeset.data.tracks

               reordered =
                 changeset
                 |> Ash.Changeset.get_argument(:order)
                 |> Enum.map(&Enum.at(tracks, &1))
                 |> Enum.with_index()
                 |> Enum.map(fn {track, position} -> %{track | position: position} end)

               Ash.Changeset.change_attribute(changeset, :tracks, reordered)
             end,
             only_when_valid?: true
    end

    update :save do
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          data = changeset.data
          session_id = data.session_id

          cover_image_url = data.cover_image_url || ""

          input = %{
            name: data.name,
            year_released: data.year_released,
            cover_image_url: if(cover_image_url == "", do: nil, else: cover_image_url),
            tracks:
              Enum.with_index(data.tracks, fn track, order ->
                %{
                  id: track.track_id,
                  order: order,
                  name: track.name,
                  duration: track.duration
                }
              end)
          }

          result =
            if is_nil(data.album_id) do
              Tunez.Music.create_album(Map.put(input, :artist_id, data.artist_id),
                load: [tracks: [:duration]],
                scope: context
              )
            else
              with {:ok, %{album: %Tunez.Music.Album{} = album}} <-
                     Ash.load(data, :album, scope: context) do
                Tunez.Music.update_album(album, input,
                  load: [tracks: [:duration]],
                  scope: context
                )
              end
            end

          case result do
            {:ok, album} ->
              {:ok, _flash} =
                Tunez.UI.put_flash(session_id, :info, "Album saved successfully", %{carry?: true},
                  scope: context
                )

              Ash.Changeset.force_change_attributes(changeset, %{
                saved_artist_id: album.artist_id,
                name: album.name,
                year_released: to_string(album.year_released),
                cover_image_url: album.cover_image_url || "",
                tracks: track_rows(album.tracks)
              })

            {:error, error} ->
              error
              |> Ash.Error.to_error_class()
              |> Map.fetch!(:errors)
              |> then(&Ash.Changeset.add_error(changeset, &1))
          end
        end)
      end
    end
  end

  # helper: track_rows/1 — shared domain-track to embedded-row storage conversion for mount and save
  defp track_rows(tracks) do
    case tracks do
      tracks when is_list(tracks) ->
        Enum.with_index(tracks, fn track, position ->
          %{track_id: track.id, name: track.name, duration: track.duration, position: position}
        end)

      _not_loaded ->
        []
    end
  end
end
