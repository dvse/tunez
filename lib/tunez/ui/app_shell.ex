defmodule Tunez.UI.AppShell do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  policies do
    policy action_type([:read, :create]) do
      authorize_if always()
    end

    policy action([:toggle_menu, :close_menu]) do
      authorize_if actor_present()
    end
  end

  attributes do
    attribute :session_id, :uuid, allow_nil?: false, primary_key?: true, public?: false
    attribute :signed_in?, :boolean, allow_nil?: false, default: false, public?: true

    attribute :email, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [allow_empty?: true]

    attribute :menu_open?, :boolean, allow_nil?: false, default: false
    attribute :avatar_seed, :string, allow_nil?: false, default: ""
    attribute :content, AshBlueprint.Type.RenderTree, public?: true
  end

  relationships do
    has_one :notifications_page, Tunez.UI.NotificationsPage,
      source_attribute: :session_id,
      destination_attribute: :session_id

    has_one :flash_stack, Tunez.UI.FlashStack,
      source_attribute: :session_id,
      destination_attribute: :session_id
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                box(:app_root, [], [
                  box(:site_header, [], [
                    box(:brand_container, [], [
                      link(:brand_link, [to: "/"], [
                        inline(:brand_icon, [], []),
                        inline(:brand_name, [], [text("Tunez")])
                      ])
                    ]),
                    box(:user_info, [], [
                      if signed_in? do
                        [
                          render(Tunez.UI.NotificationsPage, %{}),
                          box(:user_menu_container, [], [
                            box(
                              :avatar_toggle,
                              [
                                tabindex: 0,
                                role: "button",
                                on_click: :toggle_menu,
                                on_click_away: :close_menu
                              ],
                              [
                                image(
                                  :avatar,
                                  [
                                    src:
                                      "https://api.dicebear.com/9.x/shapes/svg?seed=" <>
                                        avatar_seed
                                  ],
                                  []
                                )
                              ]
                            ),
                            list(
                              :user_menu,
                              [
                                dom_id: "user-menu",
                                tabindex: 0,
                                state: [open: menu_open?]
                              ],
                              [
                                item(:user_menu_identity, [], [
                                  paragraph(:signed_in_as, [], [
                                    text("Signed in as "),
                                    strong(:email, [], [text(email)])
                                  ])
                                ]),
                                item(:user_menu_sign_out, [], [
                                  link(:sign_out_link, [to: "/sign-out"], [text("Sign out")])
                                ])
                              ]
                            )
                          ])
                        ]
                      else
                        [
                          link(:auth_link, [to: "/sign-in"], [text("Sign In")]),
                          inline(:auth_or, [], [text("or")]),
                          link(:auth_link, [to: "/register"], [text("Register")])
                        ]
                      end
                    ])
                  ]),
                  box(:app_content, [], [
                    render(Tunez.UI.FlashStack, %{}),
                    content
                  ])
                ])
              )
  end

  identities do
    identity :session_instance, [:session_id], pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    create :mount do
      accept [:signed_in?, :email]

      change fn changeset, _context ->
        seed =
          changeset
          |> Ash.Changeset.get_argument(:email)
          |> to_string()
          |> String.trim()
          |> String.downcase()
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)

        Ash.Changeset.force_change_attribute(changeset, :avatar_seed, seed)
      end

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
