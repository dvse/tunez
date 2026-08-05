defmodule Tunez.UI.ArtistFormPage do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint, Tunez.UI.Blueprint, AshLua.Resource],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  ash_blueprint do
    stylesheets([
      "../app_domain_workbench/priv/theme/styles/vscode/10-vscode-icons.css",
      "priv/static/assets/app.css"
    ])
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
    attribute :page_title, :string, allow_nil?: false, default: "New Artist", public?: true

    attribute :name, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [allow_empty?: true]

    attribute :biography, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [allow_empty?: true]

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
      public? true
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
                                  value: coalesce(name, ""),
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
                                  text(coalesce(biography, ""))
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

    read :for_session do
      description "Read artist form UI state, including mid-edit values, for one browser session."

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
      upsert_fields [:artist_id, :saved_artist_id, :page_title]

      argument :artist_id, :uuid
      change set_attribute(:artist_id, arg(:artist_id))
      change set_attribute(:page_title, "Update Artist"), where: [present(:artist_id)]

      change fn changeset, _context ->
        subject_id = Ash.Changeset.get_argument(changeset, :artist_id) || "new"
        Ash.Changeset.change_attribute(changeset, :subject_id, subject_id)
      end

      change set_attribute(:saved_artist_id, nil)

      change fn changeset, context ->
        if Ash.Changeset.get_argument(changeset, :artist_id) do
          Ash.Changeset.before_action(changeset, fn changeset ->
            with {:ok, page} <- Ash.Changeset.apply_attributes(changeset),
                 {:ok, %{artist: %Tunez.Music.Artist{} = artist}} <-
                   Ash.load(page, :artist, scope: context) do
              Ash.Changeset.force_change_attributes(changeset, %{
                name: artist.name,
                biography: artist.biography || ""
              })
            else
              {:error, error} ->
                error
                |> Ash.Error.to_error_class()
                |> Map.fetch!(:errors)
                |> then(&Ash.Changeset.add_error(changeset, &1))

              _missing_artist ->
                changeset
            end
          end)
        else
          changeset
        end
      end
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
            name: data.name,
            biography: data.biography
          }

          result =
            if is_nil(data.artist_id) do
              Tunez.Music.create_artist(input, scope: context)
            else
              with {:ok, %{artist: %Tunez.Music.Artist{} = artist}} <-
                     Ash.load(data, :artist, scope: context) do
                Tunez.Music.update_artist(artist, input, scope: context)
              end
            end

          case result do
            {:ok, artist} ->
              {:ok, _flash} =
                Tunez.UI.put_flash(
                  session_id,
                  :info,
                  "Artist saved successfully",
                  %{carry?: true},
                  scope: context
                )

              Ash.Changeset.force_change_attributes(changeset, %{
                saved_artist_id: artist.id,
                name: artist.name,
                biography: artist.biography || ""
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
end
