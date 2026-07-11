defmodule Tunez.UI.ArtistFormPage do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  routes do
    route "/artists/new" do
      location(expr(if(not is_nil(saved_artist_id), do: "/artists/" <> saved_artist_id)))
    end

    route "/artists/:artist_id/edit" do
      param(:artist_id, :uuid)
    end
  end

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
    attribute :session_id, :uuid, allow_nil?: false, primary_key?: true, public?: false
    attribute :subject_id, :string, allow_nil?: false, primary_key?: true, public?: false
    attribute :artist_id, :uuid, public?: true
    attribute :name, :string, constraints: [allow_empty?: true]
    attribute :biography, :string, constraints: [allow_empty?: true]
    attribute :saved_artist_id, :string, public?: true
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
    calculate :page_title,
              :string,
              expr(if(is_nil(artist_id), do: "New Artist", else: "Update Artist")),
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
                                  on_input: :edit
                                ],
                                []
                              ),
                            error: join(field_errors(:name), ", ")
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
                                  on_input: :edit
                                ],
                                [
                                  text(coalesce(biography, artist.biography))
                                ]
                              ),
                            error: join(field_errors(:biography), ", ")
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
    identity :session_instance, [:session_id, :subject_id], pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    create :mount do
      argument :artist_id, :uuid
      change AshBlueprint.Changes.SetSessionId
      change set_attribute(:artist_id, arg(:artist_id))

      change fn changeset, _context ->
        subject_id = Ash.Changeset.get_argument(changeset, :artist_id) || "new"
        Ash.Changeset.change_attribute(changeset, :subject_id, subject_id)
      end

      change set_attribute(:saved_artist_id, nil)
      change load(:artist)
    end

    update :edit do
      accept [:name, :biography]
    end

    update :save do
      require_atomic? false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          data = changeset.data
          session_id = data.session_id

          input = %{
            name: data.name || (data.artist && data.artist.name),
            biography: data.biography || (data.artist && data.artist.biography)
          }

          result =
            if is_nil(data.artist_id) do
              Tunez.Music.create_artist(input, scope: context)
            else
              Tunez.Music.update_artist(data.artist, input, scope: context)
            end

          case result do
            {:ok, artist} ->
              {:ok, _flash} =
                Tunez.UI.put_flash(session_id, :info, "Artist saved successfully", scope: context)

              Ash.Changeset.force_change_attribute(changeset, :saved_artist_id, artist.id)

            {:error, error} ->
              {:ok, _flash} =
                Tunez.UI.put_flash(session_id, :error, "Could not save artist data",
                  scope: context
                )

              Ash.Changeset.add_error(changeset, error)
          end
        end)
      end
    end
  end
end
