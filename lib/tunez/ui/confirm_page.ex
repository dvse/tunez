defmodule Tunez.UI.ConfirmPage do
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
    route "/confirm_new_user" do
      query :token, :string
    end

    route "/confirm_new_user/:token" do
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
    calculate :page_title, :string, expr("Confirm your account"), public?: true

    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                render(Tunez.UI.AppShell, %{
                  signed_in?: false,
                  email: "",
                  content: [
                    heading(:page_h1, [level: 1], [text("Confirm your account")]),
                    paragraph(:auth_intro, [], [
                      text("Confirm your email address to finish creating your account.")
                    ]),
                    form(
                      :auth_form,
                      [
                        dom_id: "confirm-form",
                        method: "post",
                        action: "/auth/user/confirm_new_user"
                      ],
                      [
                        hidden(:csrf_token, [name: "_csrf_token", value: csrf_token], []),
                        hidden(:confirm_token, [name: "user[confirm]", value: token], []),
                        if empty?(field_errors(:token)) do
                          nothing()
                        else
                          paragraph(:field_error, [], [
                            inline(:field_error_icon, [], []),
                            text(join(field_errors(:token), ", "))
                          ])
                        end,
                        box(:form_actions, [], [
                          button(:form_button, [type: "submit"], [text("Confirm account")])
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
