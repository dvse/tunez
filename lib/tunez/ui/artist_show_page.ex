defmodule Tunez.UI.ArtistShowPage do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  routes do
    route "/artists/:artist_id" do
      location(expr(if(deleted?, do: "/")))
      param(:artist_id, :uuid)
    end
  end

  policies do
    policy action_type([:read, :create]) do
      authorize_if always()
    end

    policy action([:follow, :unfollow, :destroy_album]) do
      authorize_if actor_present()
    end

    policy action(:destroy_artist) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    attribute :session_id, :uuid, allow_nil?: false, primary_key?: true, public?: false
    attribute :deleted?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :artist_id, :uuid, allow_nil?: false, public?: true
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
  end

  calculations do
    calculate :page_title, :string, expr(artist.name), public?: true

    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                render(Tunez.UI.AppShell, %{
                  signed_in?: not is_nil(^actor(:id)),
                  email: to_string(^actor(:email)),
                  content: [
                    render(Tunez.UI.PageHeader, %{
                      menu_id: "dropdown_" <> to_string(session_id),
                      title:
                        heading(:page_h1, [level: 1], [
                          text(artist.name),
                          text(" "),
                          if is_nil(^actor(:id)) do
                            nothing()
                          else
                            if artist.followed_by_me do
                              inline(:follow_toggle, [on_click: :unfollow], [
                                inline(:follow_toggle_icon, [state: [selected: true]], [])
                              ])
                            else
                              inline(:follow_toggle, [on_click: :follow], [
                                inline(:follow_toggle_icon, [state: [selected: false]], [])
                              ])
                            end
                          end
                        ]),
                      subtitle:
                        if empty?(artist.previous_names) do
                          nothing()
                        else
                          paragraph(:subtitle, [], [
                            text("formerly known as: "),
                            text(join(artist.previous_names, ", "))
                          ])
                        end,
                      actions:
                        if ^actor(:role) in [:admin, :editor] do
                          [
                            if ^actor(:role) == :admin do
                              link(
                                :error_link,
                                [
                                  to: "#",
                                  data: [
                                    confirm:
                                      "Are you sure you want to delete " <> artist.name <> "?"
                                  ],
                                  on_click: :destroy_artist,
                                  prevent_default: true
                                ],
                                [text("Delete Artist")]
                              )
                            else
                              nothing()
                            end,
                            link(
                              :primary_link_inverse,
                              [to: "/artists/" <> artist_id <> "/edit"],
                              [
                                text("Edit Artist")
                              ]
                            )
                          ]
                        else
                          nil
                        end
                    }),
                    box(:biography, [], [
                      each(
                        string_split(coalesce(artist.biography, ""), "\n"),
                        :biography_line,
                        [index: :biography_index],
                        [
                          text(biography_line),
                          if index(:biography_index) <
                               length(string_split(coalesce(artist.biography, ""), "\n")) - 1 do
                            break(:biography_break, [], [])
                          else
                            nothing()
                          end
                        ]
                      )
                    ]),
                    if ^actor(:role) in [:admin, :editor] do
                      link(:primary_link, [to: "/artists/" <> artist_id <> "/albums/new"], [
                        text("New Album")
                      ])
                    else
                      nothing()
                    end,
                    list(:album_list, [], [
                      each(artist.albums, :album, [key: album.id], [
                        item(:album_item, [], [
                          box(:album_root, [dom_id: "album-" <> album.id], [
                            box(:album_cover_column, [], [
                              render(Tunez.UI.CoverImage, %{image: album.cover_image_url})
                            ]),
                            box(:album_details, [], [
                              render(Tunez.UI.PageHeader, %{
                                kind: :album,
                                menu_id: "dropdown_" <> album.id,
                                title:
                                  heading(:page_h2, [level: 2], [
                                    text(
                                      album.name <>
                                        " (" <> to_string(album.year_released) <> ")"
                                    ),
                                    text(" "),
                                    if is_nil(album.duration) do
                                      nothing()
                                    else
                                      inline(:album_duration, [], [
                                        text("(" <> album.duration <> ")")
                                      ])
                                    end
                                  ]),
                                actions:
                                  if album.can_manage_album? do
                                    [
                                      link(
                                        :error_link_small,
                                        [
                                          to: "#",
                                          data: [
                                            confirm:
                                              "Are you sure you want to delete " <>
                                                album.name <> "?"
                                          ],
                                          on_click: :destroy_album,
                                          action_input: %{album_id: album.id},
                                          prevent_default: true
                                        ],
                                        [text("Delete")]
                                      ),
                                      link(
                                        :primary_link_inverse_small,
                                        [to: "/albums/" <> album.id <> "/edit"],
                                        [text("Edit")]
                                      )
                                    ]
                                  else
                                    nil
                                  end
                              }),
                              if empty?(album.tracks) do
                                box(:tracks_empty, [], [
                                  inline(:tracks_empty_icon, [], []),
                                  text(" Track data coming soon....")
                                ])
                              else
                                table(:track_table, [], [
                                  each(album.tracks, :track, [key: track.id], [
                                    row(:track_row, [], [
                                      header_cell(:track_number, [], [
                                        text(
                                          if track.number < 10,
                                            do: "0" <> to_string(track.number) <> ".",
                                            else: to_string(track.number) <> "."
                                        )
                                      ]),
                                      cell(:track_name, [], [text(track.name)]),
                                      cell(:track_duration, [], [text(track.duration)])
                                    ])
                                  ])
                                ])
                              end
                            ])
                          ])
                        ])
                      ])
                    ])
                  ]
                })
              )
  end

  identities do
    identity :session_instance, [:session_id, :artist_id], pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    create :mount do
      argument :artist_id, :uuid, allow_nil?: false
      change AshBlueprint.Changes.SetSessionId
      change set_attribute(:artist_id, arg(:artist_id))
      change set_attribute(:deleted?, false)
    end

    update :follow do
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          case Tunez.Music.follow_artist(changeset.data.artist, scope: context) do
            {:ok, _follow} -> changeset
            {:error, error} -> Ash.Changeset.add_error(changeset, error)
          end
        end)
      end
    end

    update :unfollow do
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          case Tunez.Music.unfollow_artist(changeset.data.artist, scope: context) do
            :ok -> changeset
            {:error, error} -> Ash.Changeset.add_error(changeset, error)
          end
        end)
      end
    end

    update :destroy_album do
      require_atomic? false
      argument :album_id, :uuid, allow_nil?: false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          album_id = Ash.Changeset.get_argument(changeset, :album_id)
          album = Enum.find(changeset.data.artist.albums, &(&1.id == album_id))

          case Tunez.Music.destroy_album(album, scope: context) do
            :ok ->
              {:ok, _flash} =
                Tunez.UI.put_flash(
                  changeset.data.session_id,
                  :info,
                  "Album deleted successfully",
                  scope: context
                )

              changeset

            {:error, error} ->
              Ash.Changeset.add_error(changeset, error)
          end
        end)
      end
    end

    update :destroy_artist do
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          case Tunez.Music.destroy_artist(changeset.data.artist, scope: context) do
            :ok ->
              {:ok, _flash} =
                Tunez.UI.put_flash(
                  changeset.data.session_id,
                  :info,
                  "Artist deleted successfully",
                  scope: context
                )

              Ash.Changeset.force_change_attribute(changeset, :deleted?, true)

            {:error, error} ->
              Ash.Changeset.add_error(changeset, error)
          end
        end)
      end
    end
  end
end
