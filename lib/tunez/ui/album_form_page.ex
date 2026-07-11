defmodule Tunez.UI.AlbumFormPage do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint],
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
    policy always() do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :editor)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :session_id, :uuid, allow_nil?: false, public?: false
    attribute :artist_id, :uuid, public?: true
    attribute :saved_artist_id, :string, public?: true
    attribute :album_id, :uuid, public?: true
    attribute :name, :string, constraints: [allow_empty?: true]
    attribute :year_released, :string, constraints: [allow_empty?: true]
    attribute :cover_image_url, :string, constraints: [allow_empty?: true]
    attribute :track_drafts, {:array, Tunez.Music.TrackInput}
  end

  relationships do
    has_one :artist, Tunez.Music.Artist do
      source_attribute :artist_id
      destination_attribute :id
    end

    has_one :album, Tunez.Music.Album do
      source_attribute :album_id
      destination_attribute :id
    end
  end

  calculations do
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
                                      value: coalesce(name, album.name),
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
                                      value: coalesce(year_released, album.year_released),
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
                                  value: coalesce(cover_image_url, album.cover_image_url),
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
                              [dom_id: "trackSort", reorder: [action: :reorder_tracks]],
                              [
                                each(
                                  if(is_nil(track_drafts), do: album.tracks, else: track_drafts),
                                  :track,
                                  [
                                    key: track.id,
                                    index: :track_index
                                  ],
                                  [
                                    row(:track_editor_row, [data: [id: index(:track_index)]], [
                                      cell(:track_editor_order, [], [
                                        inline(:track_editor_handle, [], [])
                                      ]),
                                      cell(:track_editor_cell, [], [
                                        render(Tunez.UI.FormControl, %{
                                          label: "Name",
                                          dom_id:
                                            "album_form_tracks_" <>
                                              to_string(index(:track_index)) <> "_name",
                                          hidden_label?: true,
                                          control:
                                            input(
                                              :form_input,
                                              [
                                                dom_id:
                                                  "album_form_tracks_" <>
                                                    to_string(index(:track_index)) <> "_name",
                                                name: "track_" <> track.id <> "_name",
                                                value: track.name,
                                                on_input: :set_track_name,
                                                action_input: %{
                                                  track_key: track.id,
                                                  name: event(:value)
                                                }
                                              ],
                                              []
                                            )
                                        })
                                      ]),
                                      cell(:track_editor_duration, [], [
                                        render(Tunez.UI.FormControl, %{
                                          label: "Duration",
                                          dom_id:
                                            "album_form_tracks_" <>
                                              to_string(index(:track_index)) <> "_duration",
                                          hidden_label?: true,
                                          control:
                                            input(
                                              :form_input,
                                              [
                                                dom_id:
                                                  "album_form_tracks_" <>
                                                    to_string(index(:track_index)) <> "_duration",
                                                name: "track_" <> track.id <> "_duration",
                                                value: track.duration,
                                                on_input: :set_track_duration,
                                                action_input: %{
                                                  track_key: track.id,
                                                  duration: event(:value)
                                                }
                                              ],
                                              []
                                            )
                                        })
                                      ]),
                                      cell(:track_editor_delete, [], [
                                        link(
                                          :track_delete_link,
                                          [
                                            to: "#",
                                            on_click: :remove_track,
                                            action_input: %{
                                              track_key: track.id
                                            },
                                            prevent_default: true
                                          ],
                                          [
                                            inline(:hidden_label, [], [text("Delete")]),
                                            inline(:track_delete_icon, [], [])
                                          ]
                                        )
                                      ])
                                    ])
                                  ]
                                )
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
    identity :session_instance, [:session_id, :artist_id, :album_id],
      nils_distinct?: false,
      pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    create :mount do
      argument :artist_id, :uuid
      argument :album_id, :uuid
      validate present([:artist_id, :album_id], exactly: 1)
      change AshBlueprint.Changes.SetSessionId
      change set_attribute(:artist_id, arg(:artist_id))
      change set_attribute(:album_id, arg(:album_id))
      change set_attribute(:saved_artist_id, nil)
      change load([:artist, :album])
    end

    update :edit do
      accept [:name, :year_released, :cover_image_url]
    end

    update :add_track do
      require_atomic? false

      change fn changeset, _context ->
        tracks = draft_tracks(changeset.data) ++ [%{}]
        Ash.Changeset.change_attribute(changeset, :track_drafts, tracks)
      end
    end

    update :remove_track do
      require_atomic? false
      argument :track_key, :uuid, allow_nil?: false

      change fn changeset, _context ->
        track_key = Ash.Changeset.get_argument(changeset, :track_key)
        tracks = Enum.reject(draft_tracks(changeset.data), &(&1.id == track_key))
        Ash.Changeset.change_attribute(changeset, :track_drafts, tracks)
      end
    end

    update :reorder_tracks do
      require_atomic? false

      argument :order, {:array, :integer},
        allow_nil?: false,
        constraints: [items: [min: 0]]

      change fn changeset, _context ->
        tracks = draft_tracks(changeset.data)

        reordered =
          changeset
          |> Ash.Changeset.get_argument(:order)
          |> Enum.map(&Enum.at(tracks, &1))
          |> Enum.reject(&is_nil/1)

        Ash.Changeset.change_attribute(changeset, :track_drafts, reordered)
      end
    end

    update :set_track_name do
      require_atomic? false
      argument :track_key, :uuid, allow_nil?: false
      argument :name, :string, allow_nil?: false, constraints: [allow_empty?: true]

      change fn changeset, _context ->
        track_key = Ash.Changeset.get_argument(changeset, :track_key)
        name = Ash.Changeset.get_argument(changeset, :name)

        tracks =
          Enum.map(
            draft_tracks(changeset.data),
            &if(&1.id == track_key, do: %{&1 | name: name}, else: &1)
          )

        Ash.Changeset.change_attribute(changeset, :track_drafts, tracks)
      end
    end

    update :set_track_duration do
      require_atomic? false
      argument :track_key, :uuid, allow_nil?: false
      argument :duration, :string, allow_nil?: false, constraints: [allow_empty?: true]

      change fn changeset, _context ->
        track_key = Ash.Changeset.get_argument(changeset, :track_key)
        duration = Ash.Changeset.get_argument(changeset, :duration)

        tracks =
          Enum.map(draft_tracks(changeset.data), fn track ->
            if track.id == track_key, do: %{track | duration: duration}, else: track
          end)

        Ash.Changeset.change_attribute(changeset, :track_drafts, tracks)
      end
    end

    update :save do
      require_atomic? false
      argument :name, :string, constraints: [allow_empty?: true]
      argument :year_released, :string, constraints: [allow_empty?: true]
      argument :cover_image_url, :string, constraints: [allow_empty?: true]

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          data = changeset.data
          session_id = data.session_id

          cover_image_url =
            Ash.Changeset.get_argument(changeset, :cover_image_url) ||
              data.cover_image_url || (data.album && data.album.cover_image_url) || ""

          input = %{
            name:
              Ash.Changeset.get_argument(changeset, :name) || data.name ||
                (data.album && data.album.name),
            year_released:
              Ash.Changeset.get_argument(changeset, :year_released) || data.year_released ||
                (data.album && data.album.year_released),
            cover_image_url: if(cover_image_url == "", do: nil, else: cover_image_url),
            tracks: draft_tracks(data)
          }

          result =
            if is_nil(data.album_id) do
              Tunez.Music.create_album(Map.put(input, :artist_id, data.artist_id), scope: context)
            else
              Tunez.Music.update_album(data.album, input, scope: context)
            end

          case result do
            {:ok, album} ->
              {:ok, _flash} =
                Tunez.UI.put_flash(session_id, :info, "Album saved successfully", scope: context)

              Ash.Changeset.force_change_attribute(changeset, :saved_artist_id, album.artist_id)

            {:error, error} ->
              {:ok, _flash} =
                Tunez.UI.put_flash(session_id, :error, "Could not save album data",
                  scope: context
                )

              Ash.Changeset.add_error(changeset, error)
          end
        end)
      end
    end
  end

  # helper: draft_tracks/1 — reuses one relationship-to-local-draft boundary across five actions.
  defp draft_tracks(%__MODULE__{track_drafts: tracks}) when is_list(tracks), do: tracks
  # helper: draft_tracks/1 — converts the declared relationship only before the first edit.
  defp draft_tracks(%__MODULE__{album: %Tunez.Music.Album{tracks: tracks}}) do
    Enum.map(tracks, &Map.merge(Map.take(&1, [:id, :name, :duration]), %{track_id: &1.id}))
  end

  # helper: draft_tracks/1 — handles the new-album relationship absence.
  defp draft_tracks(%__MODULE__{}), do: []
end
