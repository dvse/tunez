defmodule Tunez.UI.TrackDraft do
  use Ash.Resource,
    data_layer: :embedded,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy action([:create, :update, :edit, :remove]) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :track_id, :uuid, public?: true

    attribute :name, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [allow_empty?: true]

    attribute :duration, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [allow_empty?: true]

    attribute :position, :integer do
      allow_nil? false
      default 0
      public? true
      constraints min: 0
    end
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                row(:track_editor_row, [data: [id: position]], [
                  cell(:track_editor_order, [], [inline(:track_editor_handle, [], [])]),
                  cell(:track_editor_cell, [], [
                    render(Tunez.UI.FormControl, %{
                      label: "Name",
                      dom_id: "album_form_tracks_" <> to_string(position) <> "_name",
                      hidden_label?: true,
                      control:
                        input(
                          :form_input,
                          [
                            dom_id: "album_form_tracks_" <> to_string(position) <> "_name",
                            name: "name",
                            value: name,
                            on_input: :edit
                          ],
                          []
                        ),
                      error: join(field_errors(:name), ", ")
                    })
                  ]),
                  cell(:track_editor_duration, [], [
                    render(Tunez.UI.FormControl, %{
                      label: "Duration",
                      dom_id: "album_form_tracks_" <> to_string(position) <> "_duration",
                      hidden_label?: true,
                      control:
                        input(
                          :form_input,
                          [
                            dom_id: "album_form_tracks_" <> to_string(position) <> "_duration",
                            name: "duration",
                            value: duration,
                            on_input: :edit
                          ],
                          []
                        ),
                      error: join(field_errors(:duration), ", ")
                    })
                  ]),
                  cell(:track_editor_delete, [], [
                    link(
                      :track_delete_link,
                      [to: "#", on_click: :remove, prevent_default: true],
                      [
                        inline(:hidden_label, [], [text("Delete")]),
                        inline(:track_delete_icon, [], [])
                      ]
                    )
                  ])
                ])
              )
  end

  actions do
    defaults create: :*, update: :*

    update :edit do
      accept [:name, :duration]
    end

    destroy :remove do
      primary? true
    end
  end
end
