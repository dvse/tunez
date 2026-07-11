defmodule Tunez.UI.Navigation do
  use Ash.Resource,
    otp_app: :tunez,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:mount) do
      authorize_if always()
    end

    policy action(:toggle_menu) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :session_id, :uuid, allow_nil?: false, public?: false
    attribute :signed_in?, :boolean, allow_nil?: false, default: false, public?: true

    attribute :email, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [allow_empty?: true]

    attribute :avatar_url, :string,
      allow_nil?: false,
      default: "",
      constraints: [allow_empty?: true]

    attribute :menu_open?, :boolean, allow_nil?: false, default: false
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
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
                            [tabindex: 0, role: "button", on_click: :toggle_menu],
                            [image(:avatar, [src: avatar_url], [])]
                          ),
                          list(
                            :user_menu,
                            [
                              dom_id: "user-menu",
                              tabindex: 0,
                              open: menu_open?,
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
      change AshBlueprint.Changes.SetSessionId

      change fn changeset, _context ->
        email =
          changeset
          |> Ash.Changeset.get_argument_or_attribute(:email)
          |> String.trim()
          |> String.downcase()

        seed = :crypto.hash(:sha256, email) |> Base.encode16(case: :lower)

        Ash.Changeset.force_change_attribute(
          changeset,
          :avatar_url,
          "https://api.dicebear.com/9.x/shapes/svg?seed=#{seed}"
        )
      end
    end

    update :toggle_menu do
      change atomic_update(:menu_open?, expr(not menu_open?))
    end
  end
end
