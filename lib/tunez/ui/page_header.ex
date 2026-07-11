defmodule Tunez.UI.PageHeader do
  use Ash.Resource,
    data_layer: :embedded,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy action_type(:create) do
      authorize_if always()
    end
  end

  attributes do
    attribute :kind, :atom do
      allow_nil? false
      default :responsive
      public? true
      constraints one_of: [:album, :fixed, :responsive, :simple]
    end

    attribute :menu_id, :string, public?: true
    attribute :title, AshBlueprint.Type.RenderTree, allow_nil?: false, public?: true
    attribute :subtitle, AshBlueprint.Type.RenderTree, public?: true
    attribute :actions, AshBlueprint.Type.RenderTree, public?: true
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                header(:page_header, [data: [kind: kind]], [
                  box(:page_header_title, [], [title, subtitle]),
                  if is_nil(actions) do
                    nothing()
                  else
                    if kind == :fixed do
                      box(:page_header_actions, [], [
                        box(:page_header_actions_outer, [dom_id: menu_id, tabindex: 0], [
                          box(:page_header_actions_inner, [], [actions])
                        ])
                      ])
                    else
                      box(:page_header_actions_responsive, [], [
                        box(:page_header_toggle, [tabindex: 0, role: "button"], [
                          inline(:page_header_toggle_icon, [], [])
                        ]),
                        box(:page_header_menu, [dom_id: menu_id, tabindex: 0], [
                          box(:page_header_actions_responsive_inner, [], [actions])
                        ])
                      ])
                    end
                  end
                ])
              )
  end

  actions do
    create :create do
      primary? true
      accept [:kind, :menu_id, :title, :subtitle, :actions]
    end
  end
end
