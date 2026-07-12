defmodule Tunez.UI.MagicSignInPage do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  routes do
    # Static query alias for the Datastar bridge; email links keep the path-token route below.
    route "/magic_link" do
      query :token, :string
    end

    route "/magic_link/:token" do
      param(:token, :string)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    attribute :session_id, :uuid, allow_nil?: false, primary_key?: true, public?: false
    attribute :csrf_token, :string, allow_nil?: false, sensitive?: true, public?: false
    attribute :token, :string, allow_nil?: false, sensitive?: true, public?: true
  end

  relationships do
    has_one :app_shell, Tunez.UI.AppShell,
      source_attribute: :session_id,
      destination_attribute: :session_id
  end

  calculations do
    calculate :page_title, :string, expr("Finish signing in"), public?: true

    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                render(Tunez.UI.AppShell, %{
                  signed_in?: false,
                  email: "",
                  content: [
                    heading(:page_h1, [level: 1], [text("Finish signing in")]),
                    paragraph(:auth_intro, [], [
                      text("Use the button below to finish signing in with your email link.")
                    ]),
                    form(
                      :auth_form,
                      [
                        dom_id: "magic-sign-in-form",
                        method: "post",
                        action: "/auth/user/magic_link"
                      ],
                      [
                        hidden(:csrf_token, [name: "_csrf_token", value: csrf_token], []),
                        hidden(:magic_link_token, [name: "user[token]", value: token], []),
                        if empty?(field_errors(:token)) do
                          nothing()
                        else
                          paragraph(:field_error, [], [
                            inline(:field_error_icon, [], []),
                            text(join(field_errors(:token), ", "))
                          ])
                        end,
                        box(:form_actions, [], [
                          button(:form_button, [type: "submit"], [text("Sign in")])
                        ])
                      ]
                    )
                  ]
                })
              )
  end

  identities do
    identity :session_instance, [:session_id], pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    create :mount do
      change set_attribute(:csrf_token, context(:csrf_token))
      argument :token, :string, allow_nil?: false
      change set_attribute(:token, arg(:token))
      change AshBlueprint.Changes.SetSessionId
      change Tunez.UI.Changes.BeginPageLife
    end
  end
end
