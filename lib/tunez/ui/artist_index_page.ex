defmodule Tunez.UI.ArtistIndexPage do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  route("/", query: [:q, :sort_by, :limit, :offset])

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :session_id, :uuid, allow_nil?: false, public?: false

    attribute :q, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [allow_empty?: true]

    attribute :sort_by, :atom do
      allow_nil? false
      default :"-updated_at"
      public? true

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
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                render(Tunez.UI.AppShell, %{
                  signed_in?: not is_nil(^actor(:id)),
                  email: to_string(^actor(:email)),
                  content: [
                    render(Tunez.UI.PageHeader, %{
                      kind: :fixed,
                      menu_id: "dropdown_" <> id,
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
                              inline(:sort_gap, [], []),
                              select(
                                :sort_select,
                                [dom_id: "sort_by", name: "sort_by"],
                                [
                                  each(
                                    [
                                      %{label: "recently updated", value: "-updated_at"},
                                      %{label: "recently added", value: "-inserted_at"},
                                      %{label: "name", value: "name"},
                                      %{label: "number of albums", value: "-album_count"},
                                      %{
                                        label: "latest album release",
                                        value: "--latest_album_year_released"
                                      },
                                      %{label: "popularity", value: "-follower_count"},
                                      %{label: "followed artists first", value: "-followed_by_me"}
                                    ],
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
                            on_submit: :search,
                            action_input: %{query: q}
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
                                    name: "query",
                                    value: q,
                                    on_input: :set_query,
                                    action_input: %{query: event(:value)}
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
                        link(
                          :primary_link_inverse,
                          [
                            to:
                              "/?sort_by=" <>
                                to_string(sort_by) <>
                                "&q=" <>
                                q <>
                                "&limit=" <>
                                to_string(limit) <>
                                "&offset=" <>
                                to_string(if(offset > limit, do: offset - limit, else: 0)),
                            data: [role: "previous-page"],
                            disabled: offset == 0
                          ],
                          [text("« Previous")]
                        ),
                        link(
                          :primary_link_inverse,
                          [
                            to:
                              "/?sort_by=" <>
                                to_string(sort_by) <>
                                "&q=" <>
                                q <>
                                "&limit=" <>
                                to_string(limit) <>
                                "&offset=" <>
                                to_string(offset + limit),
                            data: [role: "next-page"],
                            disabled: is_nil(next_artist)
                          ],
                          [text("Next »")]
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
      accept [:q, :sort_by, :limit, :offset]
      change AshBlueprint.Changes.SetSessionId
    end

    update :search do
      argument :query, :string do
        allow_nil? false
        constraints allow_empty?: true
      end

      change set_attribute(:q, arg(:query))
      change set_attribute(:offset, 0)
    end

    update :set_query do
      argument :query, :string, allow_nil?: false, constraints: [allow_empty?: true]
      change set_attribute(:q, arg(:query))
    end

    update :change_sort do
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

      change set_attribute(:sort_by, arg(:sort_by))
      change set_attribute(:offset, 0)
    end
  end

  defmodule ArtistsRelationship do
    @moduledoc false
    use Ash.Resource.ManualRelationship

    def load(records, opts, context) do
      mode = Keyword.fetch!(opts, :mode)

      scope_opts = Ash.Scope.to_opts(context, authorize?: context.authorize?)

      results =
        Enum.map(records, fn page ->
          {limit, offset} =
            case mode do
              :page -> {page.limit, page.offset}
              :next -> {1, page.offset + page.limit}
            end

          case Tunez.Music.browse_artists(
                 %{
                   query: page.q,
                   sort_by: page.sort_by,
                   limit: limit,
                   offset: offset
                 },
                 scope_opts
               ) do
            {:ok, artists} ->
              if mode == :next, do: List.first(artists), else: artists

            {:error, error} ->
              raise error
          end
        end)

      {:ok, results}
    end
  end
end
