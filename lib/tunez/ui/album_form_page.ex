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

  route("/artists/:artist_id/albums/new",
    location:
      expr(
        if not is_nil(saved_artist_id) do
          "/artists/" <> saved_artist_id
        end
      )
  )

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
    attribute :year_released, :integer
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
                                      value: coalesce(name, album.name),
                                      on_input: :set_name,
                                      action_input: %{name: event(:value)}
                                    ],
                                    []
                                  )
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
                                      value: coalesce(year_released, album.year_released),
                                      on_input: :set_year_released,
                                      action_input: %{year_released: event(:value)}
                                    ],
                                    []
                                  )
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
                                  value: coalesce(cover_image_url, album.cover_image_url),
                                  on_input: :set_cover_image_url,
                                  action_input: %{cover_image_url: event(:value)}
                                ],
                                []
                              )
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
                                  coalesce(track_drafts, coalesce(album.tracks, [])),
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
      # handoff state is mount-reset: re-entry always gives a fresh form
      change set_attribute(:saved_artist_id, nil)
      change set_attribute(:track_drafts, nil)
      change load([:artist, :album])
    end

    update :set_name do
      accept [:name]
    end

    update :set_year_released do
      accept [:year_released]
    end

    update :set_cover_image_url do
      accept [:cover_image_url]
    end

    update :add_track do
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(
          changeset,
          :track_drafts,
          editable_tracks(changeset) ++ [%{}]
        )
      end
    end

    update :remove_track do
      require_atomic? false
      argument :track_key, :uuid, allow_nil?: false

      change fn changeset, _context ->
        track_key = Ash.Changeset.get_argument(changeset, :track_key)

        tracks =
          Enum.reject(
            editable_tracks(changeset),
            &(&1.id == track_key)
          )

        Ash.Changeset.change_attribute(changeset, :track_drafts, tracks)
      end
    end

    update :reorder_tracks do
      require_atomic? false

      argument :order, {:array, :integer},
        allow_nil?: false,
        constraints: [items: [min: 0]]

      change fn changeset, _context ->
        tracks = editable_tracks(changeset)

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
            editable_tracks(changeset),
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
          Enum.map(
            editable_tracks(changeset),
            &if(&1.id == track_key,
              do: %{&1 | duration: duration},
              else: &1
            )
          )

        Ash.Changeset.change_attribute(changeset, :track_drafts, tracks)
      end
    end

    update :save do
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          album = changeset.data.album

          cover_image_url =
            changeset.data.cover_image_url || (album && album.cover_image_url) || ""

          input = %{
            name: changeset.data.name || (album && album.name) || "",
            year_released: changeset.data.year_released || (album && album.year_released),
            cover_image_url: if(cover_image_url == "", do: nil, else: cover_image_url),
            tracks: editable_tracks(changeset)
          }

          result =
            if is_nil(changeset.data.album_id) do
              Tunez.Music.create_album(
                Map.put(input, :artist_id, changeset.data.artist_id),
                scope: context
              )
            else
              Tunez.Music.update_album(changeset.data.album, input, scope: context)
            end

          case result do
            {:ok, album} ->
              {:ok, _flash} =
                Tunez.UI.put_flash(
                  changeset.data.session_id,
                  :info,
                  "Album saved successfully",
                  scope: context
                )

              Ash.Changeset.force_change_attribute(
                changeset,
                :saved_artist_id,
                album.artist_id
              )

            {:error, error} ->
              # the domain error IS the dispatch result
              Ash.Changeset.add_error(changeset, error)
          end
        end)
      end
    end
  end

  # helper: editable_tracks/1 — shared relationship-to-draft projection for five track actions
  defp editable_tracks(changeset) do
    changeset.data.track_drafts ||
      if is_nil(changeset.data.album) do
        []
      else
        Enum.map(changeset.data.album.tracks, fn track ->
          %{id: track.id, track_id: track.id, name: track.name, duration: track.duration}
        end)
      end
  end
end
