defmodule Tunez.UI.ResetPage do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  ash_blueprint do
    initial(:csrf_token, expr(context(:csrf_token)))
  end

  routes do
    route "/reset"

    route "/password-reset/:token" do
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
    attribute :token, :string, sensitive?: true, public?: true
    attribute :email, :string, constraints: [allow_empty?: true]

    attribute :password, :string,
      constraints: [allow_empty?: true, min_length: 8],
      sensitive?: true

    attribute :password_confirmation, :string,
      constraints: [allow_empty?: true],
      sensitive?: true
  end

  relationships do
    has_one :app_shell, Tunez.UI.AppShell,
      source_attribute: :session_id,
      destination_attribute: :session_id
  end

  calculations do
    calculate :page_title,
              :string,
              expr(if(is_nil(token), do: "Reset password", else: "Choose a new password")),
              public?: true

    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                render(Tunez.UI.AppShell, %{
                  signed_in?: false,
                  email: "",
                  content: [
                    heading(:page_h1, [level: 1], [
                      text(if(is_nil(token), do: "Reset password", else: "Choose a new password"))
                    ]),
                    if is_nil(token) do
                      form(
                        :auth_form,
                        [
                          dom_id: "reset-request-form",
                          method: "post",
                          action: "/auth/user/password/reset_request"
                        ],
                        [
                          hidden(
                            :csrf_token,
                            [name: "_csrf_token", value: csrf_token],
                            []
                          ),
                          box(:form_stack, [], [
                            render(Tunez.UI.FormControl, %{
                              label: "Email",
                              dom_id: "reset-email",
                              control:
                                input(
                                  :form_input,
                                  [
                                    dom_id: "reset-email",
                                    name: "user[email]",
                                    type: "email",
                                    autocomplete: "email",
                                    value: email,
                                    required: true,
                                    on_input: :edit,
                                    action_input: %{email: event(:value)}
                                  ],
                                  []
                                ),
                              error: join(field_errors(:email), ", ")
                            }),
                            box(:form_actions, [], [
                              button(:form_button, [type: "submit"], [
                                text("Request reset password link")
                              ])
                            ])
                          ])
                        ]
                      )
                    else
                      form(
                        :auth_form,
                        [
                          dom_id: "password-reset-form",
                          method: "post",
                          action: "/auth/user/password/reset"
                        ],
                        [
                          hidden(
                            :csrf_token,
                            [name: "_csrf_token", value: csrf_token],
                            []
                          ),
                          hidden(:reset_token, [name: "user[reset_token]", value: token], []),
                          box(:form_stack, [], [
                            render(Tunez.UI.FormControl, %{
                              label: "Password",
                              dom_id: "reset-password",
                              control:
                                input(
                                  :form_input,
                                  [
                                    dom_id: "reset-password",
                                    name: "user[password]",
                                    type: "password",
                                    autocomplete: "new-password",
                                    minlength: 8,
                                    required: true,
                                    on_input: :edit,
                                    action_input: %{password: event(:value)}
                                  ],
                                  []
                                ),
                              error: join(field_errors(:password), ", ")
                            }),
                            render(Tunez.UI.FormControl, %{
                              label: "Password Confirmation",
                              dom_id: "reset-password-confirmation",
                              control:
                                input(
                                  :form_input,
                                  [
                                    dom_id: "reset-password-confirmation",
                                    name: "user[password_confirmation]",
                                    type: "password",
                                    autocomplete: "new-password",
                                    minlength: 8,
                                    required: true,
                                    on_input: :edit,
                                    action_input: %{password_confirmation: event(:value)}
                                  ],
                                  []
                                ),
                              error: join(field_errors(:password_confirmation), ", ")
                            }),
                            box(:form_actions, [], [
                              button(:form_button, [type: "submit"], [
                                text("Reset password")
                              ])
                            ])
                          ])
                        ]
                      )
                    end,
                    paragraph(:auth_switch, [], [
                      link(:auth_secondary_link, [to: "/sign-in"], [text("Back to sign in")])
                    ])
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
      argument :token, :string
      change set_attribute(:token, arg(:token))
      change AshBlueprint.Changes.SetSessionId
    end

    update :edit do
      accept [:email, :password, :password_confirmation]
      validate confirm(:password, :password_confirmation)
    end
  end
end
