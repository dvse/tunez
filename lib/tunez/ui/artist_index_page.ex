defmodule Tunez.UI.ArtistIndexPage do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  # The sort vocabulary — ONE source for the attribute constraint, the
  # select options, and the mount whitelist. Values are upstream
  # sort_input strings.
  @sort_options [
    {"recently updated", "-updated_at"},
    {"recently added", "-inserted_at"},
    {"name", "name"},
    {"number of albums", "-album_count"},
    {"latest album release", "--latest_album_year_released"},
    {"popularity", "-follower_count"},
    {"followed artists first", "-followed_by_me"}
  ]

  @sort_option_maps Enum.map(@sort_options, fn {label, value} ->
                      %{label: label, value: value}
                    end)

  ets do
    private? false
  end

  routes do
    route "/" do
      query :q, :string
      query :sort_by, :string
      query :limit, :integer
      query :offset, :integer
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    attribute :session_id, :uuid, allow_nil?: false, primary_key?: true, public?: false

    attribute :q, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [allow_empty?: true]

    attribute :sort_by, :atom do
      allow_nil? false
      default :"-updated_at"
      public? true

      constraints one_of: Enum.map(@sort_options, fn {_label, value} -> String.to_atom(value) end)
    end

    attribute :limit, :integer,
      allow_nil?: false,
      default: 12,
      public?: true,
      constraints: [min: 1, max: 48]

    attribute :offset, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0]
  end

  relationships do
    has_one :app_shell, Tunez.UI.AppShell,
      source_attribute: :session_id,
      destination_attribute: :session_id

    has_many :page_headers, Tunez.UI.PageHeader,
      source_attribute: :session_id,
      destination_attribute: :session_id

    has_many :artists, Tunez.Music.Artist do
      no_attributes? true
      manual {Tunez.UI.ArtistIndexPage.ArtistsRelationship, mode: :page}
    end

    has_one :next_artist, Tunez.Music.Artist do
      no_attributes? true
      manual {Tunez.UI.ArtistIndexPage.ArtistsRelationship, mode: :next}
    end
  end

  calculations do
    calculate :page_title, :string, expr("Artists"), public?: true

    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                render(Tunez.UI.AppShell, %{
                  signed_in?: not is_nil(^actor(:id)),
                  email: to_string(^actor(:email)),
                  content: [
                    render(Tunez.UI.PageHeader, %{
                      kind: :fixed,
                      menu_id: "dropdown_" <> to_string(session_id),
                      title: heading(:page_h1, [level: 1], [text("Artists")]),
                      actions: [
                        form(
                          :sort_form,
                          [
                            data: [role: "artist-sort"],
                            on_change: :change_sort,
                            action_input: %{sort_by: event(:value)}
                          ],
                          [
                            box(:sort_control, [], [
                              label(:field_label, [for: "sort_by"], [text("sort by:")]),
                              select(
                                :sort_select,
                                [dom_id: "sort_by", name: "sort_by"],
                                [
                                  each(
                                    @sort_option_maps,
                                    :sort_option,
                                    [key: sort_option.value],
                                    [
                                      option(
                                        :sort_option,
                                        [
                                          value: sort_option.value,
                                          selected: to_string(sort_by) == sort_option.value
                                        ],
                                        [text(sort_option.label)]
                                      )
                                    ]
                                  )
                                ]
                              )
                            ])
                          ]
                        ),
                        form(
                          :search_form,
                          [
                            data: [role: "artist-search"],
                            on_submit: :search
                          ],
                          [
                            inline(:search_icon, [], []),
                            render(Tunez.UI.FormControl, %{
                              label: "Search",
                              dom_id: "search-text",
                              hidden_label?: true,
                              control:
                                input(
                                  :search_input,
                                  [
                                    dom_id: "search-text",
                                    name: "q",
                                    value: q,
                                    on_input: :set_query
                                  ],
                                  []
                                )
                            })
                          ]
                        ),
                        if ^actor(:role) == :admin do
                          link(:primary_link, [to: "/artists/new"], [text("New Artist")])
                        else
                          nothing()
                        end
                      ]
                    }),
                    if empty?(artists) do
                      box(:empty_state, [], [
                        inline(:empty_icon, [], []),
                        break(:line, [], []),
                        text(" No artist data to display!")
                      ])
                    else
                      nothing()
                    end,
                    list(:artist_grid, [], [
                      each(artists, :artist, [key: artist.id], [
                        item(:artist_card_item, [], [
                          render(Tunez.UI.ArtistCard, %{
                            id: artist.id,
                            name: artist.name,
                            cover_image_url: artist.cover_image_url,
                            followed?: artist.followed_by_me,
                            follower_count: artist.follower_count,
                            album_count: artist.album_count,
                            latest_album_year: artist.latest_album_year_released
                          })
                        ])
                      ])
                    ]),
                    if not is_nil(next_artist) or offset > 0 do
                      box(:pagination, [], [
                        button(
                          :primary_link_inverse,
                          [
                            type: :button,
                            on_click: :previous_page,
                            data: [role: "previous-page"],
                            disabled: offset == 0
                          ],
                          [text("\u00ab Previous")]
                        ),
                        button(
                          :primary_link_inverse,
                          [
                            type: :button,
                            on_click: :next_page,
                            data: [role: "next-page"],
                            disabled: is_nil(next_artist)
                          ],
                          [text("Next \u00bb")]
                        )
                      ])
                    else
                      nothing()
                    end
                  ]
                })
              )
  end

  identities do
    identity :session_instance, [:session_id], pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    create :mount do
      accept [:q, :limit, :offset]
      argument :sort_by, :string
      change AshBlueprint.Changes.SetSessionId
      change Tunez.UI.Changes.BeginPageLife

      change set_attribute(:sort_by, arg(:sort_by)),
        where: [
          argument_in(:sort_by, Enum.map(@sort_options, fn {_label, value} -> value end))
        ]
    end

    update :search do
      accept [:q]
      change set_attribute(:offset, 0)
    end

    update :set_query do
      accept [:q]
    end

    update :change_sort do
      accept [:sort_by]
      change set_attribute(:offset, 0)
    end

    update :previous_page do
      require_atomic? false

      change fn changeset, _context ->
        data = changeset.data
        Ash.Changeset.change_attribute(changeset, :offset, max(data.offset - data.limit, 0))
      end
    end

    update :next_page do
      require_atomic? false

      change fn changeset, _context ->
        data = changeset.data
        Ash.Changeset.change_attribute(changeset, :offset, data.offset + data.limit)
      end
    end
  end

  defmodule ArtistsRelationship do
    @moduledoc false
    use Ash.Resource.ManualRelationship

    def load(records, opts, context) do
      mode = Keyword.fetch!(opts, :mode)
      scope_opts = Ash.Scope.to_opts(context, authorize?: context.authorize?)

      {:ok,
       Enum.map(records, fn page ->
         {limit, offset} =
           if mode == :next, do: {1, page.offset + page.limit}, else: {page.limit, page.offset}

         artists =
           Tunez.Music.browse_artists!(
             page.q,
             %{sort_by: to_string(page.sort_by), limit: limit, offset: offset},
             scope_opts
           )

         if mode == :next, do: List.first(artists), else: artists
       end)}
    end
  end
end
