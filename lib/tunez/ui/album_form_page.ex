defmodule Tunez.UI.AlbumFormPage do
  use Ash.Resource,
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
    attribute :name, :string, constraints: [allow_empty?: true]
    attribute :year_released, :string, constraints: [allow_empty?: true]
    attribute :cover_image_url, :string, constraints: [allow_empty?: true]
    attribute :tracks, {:array, Tunez.UI.TrackDraft}, allow_nil?: false, default: []
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
    end

    belongs_to :album, Tunez.Music.Album do
      define_attribute? false
      source_attribute :album_id
      read_action :manageable
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
                                each(tracks, :track, [key: track.id], [
                                  render(Tunez.UI.TrackDraft, track)
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

    create :mount do
      argument :artist_id, :uuid
      argument :album_id, :uuid
      validate present([:artist_id, :album_id], exactly: 1)
      change AshBlueprint.Changes.SetSessionId
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
        Ash.Changeset.after_action(changeset, fn _changeset, page ->
          tracks = if is_struct(page.album, Tunez.Music.Album), do: page.album.tracks, else: []

          drafts =
            tracks
            |> Enum.with_index()
            |> Enum.map(fn {track, position} ->
              minutes = div(track.duration_seconds, 60)

              seconds =
                track.duration_seconds
                |> rem(60)
                |> Integer.to_string()
                |> String.pad_leading(2, "0")

              %{
                track_id: track.id,
                name: track.name,
                duration: "#{minutes}:#{seconds}",
                position: position
              }
            end)

          Tunez.UI.initialize_album_tracks(page, drafts, scope: context)
        end)
      end

      change load([:artist, album: [:can_manage_album?]])
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

    update :initialize_tracks do
      accept [:tracks]
      require_atomic? false
    end

    update :edit do
      accept [:name, :year_released, :cover_image_url]
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
        constraints: [items: [min: 0]]

      change fn changeset, _context ->
        tracks = changeset.data.tracks

        reordered =
          changeset
          |> Ash.Changeset.get_argument(:order)
          |> Enum.map(&Enum.at(tracks, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.with_index()
          |> Enum.map(fn {track, position} -> %{track | position: position} end)

        Ash.Changeset.change_attribute(changeset, :tracks, reordered)
      end
    end

    update :save do
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          data = changeset.data
          session_id = data.session_id

          cover_image_url =
            data.cover_image_url || (data.album && data.album.cover_image_url) || ""

          input = %{
            name: data.name || (data.album && data.album.name),
            year_released: data.year_released || (data.album && data.album.year_released),
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
end
