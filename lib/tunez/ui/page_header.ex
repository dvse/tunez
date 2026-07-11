defmodule Tunez.UI.PageHeader do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :session_id, :uuid, allow_nil?: false, public?: false

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
    attribute :menu_open?, :boolean, allow_nil?: false, default: false
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                header(:page_header, [data: [kind: kind]], [
                  box(:page_header_title, [], [title, subtitle]),
                  if empty?(actions) do
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
                        box(
                          :page_header_toggle,
                          [
                            tabindex: 0,
                            role: "button",
                            on_click: :toggle_menu,
                            on_click_away: :close_menu
                          ],
                          [inline(:page_header_toggle_icon, [], [])]
                        ),
                        box(
                          :page_header_menu,
                          [dom_id: menu_id, tabindex: 0, state: [open: menu_open?]],
                          [box(:page_header_actions_responsive_inner, [], [actions])]
                        )
                      ])
                    end
                  end
                ])
              )
  end

  identities do
    identity :session_instance, [:session_id, :menu_id],
      nils_distinct?: false,
      pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    create :mount do
      accept [:kind, :menu_id, :title, :subtitle, :actions]
      change AshBlueprint.Changes.SetSessionId
    end

    update :toggle_menu do
      change atomic_update(:menu_open?, expr(not menu_open?))
    end

    update :close_menu do
      change set_attribute(:menu_open?, false)
    end
  end
end
