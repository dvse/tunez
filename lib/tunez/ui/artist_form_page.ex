defmodule Tunez.UI.ArtistFormPage do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  route("/artists/new",
    location:
      expr(
        if not is_nil(saved_artist_id) do
          "/artists/" <> saved_artist_id
        end
      )
  )

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action(:mount) do
      forbid_unless actor_attribute_equals(:role, :editor)
      authorize_if expr(not is_nil(^arg(:artist_id)))
    end

    policy action_type([:read, :update]) do
      authorize_if actor_attribute_equals(:role, :editor)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :session_id, :uuid, allow_nil?: false, public?: false
    attribute :artist_id, :uuid, public?: true
    attribute :name, :string, constraints: [allow_empty?: true]
    attribute :biography, :string, constraints: [allow_empty?: true]
    attribute :saved_artist_id, :string, public?: true
  end

  relationships do
    has_one :artist, Tunez.Music.Artist do
      source_attribute :artist_id
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
                          text(if(is_nil(artist_id), do: "New Artist", else: "Update Artist"))
                        ])
                    }),
                    form(
                      :artist_form,
                      [
                        dom_id: "artist_form",
                        on_submit: :save
                      ],
                      [
                        box(:form_stack, [], [
                          render(Tunez.UI.FormControl, %{
                            label: "Name",
                            dom_id: "artist_form_name",
                            control:
                              input(
                                :form_input,
                                [
                                  dom_id: "artist_form_name",
                                  name: "name",
                                  value: coalesce(name, artist.name),
                                  on_input: :set_name,
                                  action_input: %{name: event(:value)}
                                ],
                                []
                              )
                          }),
                          render(Tunez.UI.FormControl, %{
                            label: "Biography",
                            dom_id: "artist_form_biography",
                            control:
                              textarea(
                                :form_textarea,
                                [
                                  dom_id: "artist_form_biography",
                                  name: "biography",
                                  on_input: :set_biography,
                                  action_input: %{biography: event(:value)}
                                ],
                                [
                                  text(coalesce(biography, coalesce(artist.biography, "")))
                                ]
                              )
                          }),
                          box(:form_actions, [], [button(:form_button, [], [text("Save")])])
                        ])
                      ]
                    )
                  ]
                })
              )
  end

  identities do
    identity :session_instance, [:session_id, :artist_id],
      nils_distinct?: false,
      pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    create :mount do
      argument :artist_id, :uuid
      change AshBlueprint.Changes.SetSessionId
      change set_attribute(:artist_id, arg(:artist_id))
      # handoff state is mount-reset: re-entry always gives a fresh form
      change set_attribute(:saved_artist_id, nil)
      change load(:artist)
    end

    update :set_name do
      accept [:name]
    end

    update :set_biography do
      accept [:biography]
    end

    update :save do
      require_atomic? false

      # submit fields bind BY NAME; live per-field drafts back them up
      argument :name, :string, constraints: [allow_empty?: true]
      argument :biography, :string, constraints: [allow_empty?: true]

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          input = %{
            name:
              Ash.Changeset.get_argument(changeset, :name) || changeset.data.name ||
                (changeset.data.artist && changeset.data.artist.name) || "",
            biography:
              Ash.Changeset.get_argument(changeset, :biography) || changeset.data.biography ||
                (changeset.data.artist && changeset.data.artist.biography) || ""
          }

          result =
            if is_nil(changeset.data.artist_id) do
              Tunez.Music.create_artist(input, scope: context)
            else
              Tunez.Music.update_artist(changeset.data.artist, input, scope: context)
            end

          case result do
            {:ok, artist} ->
              {:ok, _flash} =
                Tunez.UI.put_flash(
                  changeset.data.session_id,
                  :info,
                  "Artist saved successfully",
                  scope: context
                )

              Ash.Changeset.force_change_attribute(changeset, :saved_artist_id, artist.id)

            {:error, error} ->
              # the domain error IS the dispatch result — field-path'd
              # errors reach the bound controls, nothing converts to flash
              Ash.Changeset.add_error(changeset, error)
          end
        end)
      end
    end
  end
end
