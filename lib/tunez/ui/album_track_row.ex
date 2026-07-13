defmodule Tunez.UI.AlbumTrackRow do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: :embedded,
    extensions: [AshBlueprint, AshLua.Resource],
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
                    box(:track_field, [], [
                      input(
                        :form_input,
                        [
                          dom_id: "album_form_tracks_" <> to_string(position) <> "_name",
                          aria: [label: "Name"],
                          name: "name",
                          value: name,
                          on_input: :edit
                        ],
                        []
                      ),
                      if empty?(field_errors(:name)) do
                        nothing()
                      else
                        paragraph(:field_error, [role: "alert"], [
                          inline(:field_error_icon, [], []),
                          text(join(field_errors(:name), ", "))
                        ])
                      end
                    ])
                  ]),
                  cell(:track_editor_duration, [], [
                    box(:track_field, [], [
                      input(
                        :form_input,
                        [
                          dom_id: "album_form_tracks_" <> to_string(position) <> "_duration",
                          aria: [label: "Duration"],
                          name: "duration",
                          value: duration,
                          on_input: :edit
                        ],
                        []
                      ),
                      if empty?(field_errors(:duration)) do
                        nothing()
                      else
                        paragraph(:field_error, [role: "alert"], [
                          inline(:field_error_icon, [], []),
                          text(join(field_errors(:duration), ", "))
                        ])
                      end
                    ])
                  ]),
                  cell(:track_editor_delete, [], [
                    button(
                      :track_delete_link,
                      [type: :button, on_click: :remove, aria: [label: "Delete"]],
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
    defaults create: :*

    update :edit do
      primary? true
      accept [:name, :duration]
    end

    destroy :remove do
      primary? true
    end
  end
end
