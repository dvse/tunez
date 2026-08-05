defmodule Tunez.UI.FormControl do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: :embedded,
    extensions: [AshBlueprint, Tunez.UI.Blueprint, AshLua.Resource],
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    attribute :label, :string,
      allow_nil?: false,
      public?: true,
      constraints: [allow_empty?: true]

    attribute :dom_id, :string, public?: true
    attribute :hidden_label?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :control, AshBlueprint.Type.RenderTree, allow_nil?: false, public?: true
    attribute :error, :string, public?: true
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                box(:form_control, [], [
                  if hidden_label? do
                    label(:hidden_label, [for: dom_id], [text(label)])
                  else
                    label(:field_label, [for: dom_id], [text(label)])
                  end,
                  control,
                  if is_nil(error) or error == "" do
                    nothing()
                  else
                    paragraph(:field_error, [], [
                      inline(:field_error_icon, [data: %{icon: "error"}], []),
                      text(error)
                    ])
                  end
                ])
              )
  end

  actions do
    defaults create: :*
  end
end
