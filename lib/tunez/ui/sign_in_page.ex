defmodule Tunez.UI.SignInPage do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint, AshLua.Resource],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  routes do
    route "/sign-in"
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    attribute :session_id, :uuid, allow_nil?: false, primary_key?: true, public?: false
    attribute :csrf_token, :string, allow_nil?: false, sensitive?: true, public?: false
    attribute :email, :string, constraints: [allow_empty?: true]
    attribute :password, :string, constraints: [allow_empty?: true], sensitive?: true
  end

  relationships do
    has_one :app_shell, Tunez.UI.AppShell,
      source_attribute: :session_id,
      destination_attribute: :session_id
  end

  calculations do
    calculate :page_title, :string, expr("Sign in"), public?: true

    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                render(Tunez.UI.AppShell, %{
                  signed_in?: false,
                  email: "",
                  content: [
                    heading(:page_h1, [level: 1], [text("Sign in")]),
                    form(
                      :auth_form,
                      [
                        dom_id: "sign-in-form",
                        method: "post",
                        action: "/auth/user/password/sign_in"
                      ],
                      [
                        hidden(:csrf_token, [name: "_csrf_token", value: csrf_token], []),
                        box(:form_stack, [], [
                          render(Tunez.UI.FormControl, %{
                            label: "Email",
                            dom_id: "sign-in-email",
                            control:
                              input(
                                :form_input,
                                [
                                  dom_id: "sign-in-email",
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
                          render(Tunez.UI.FormControl, %{
                            label: "Password",
                            dom_id: "sign-in-password",
                            control:
                              input(
                                :form_input,
                                [
                                  dom_id: "sign-in-password",
                                  name: "user[password]",
                                  type: "password",
                                  autocomplete: "current-password",
                                  required: true,
                                  on_input: :edit,
                                  action_input: %{password: event(:value)}
                                ],
                                []
                              ),
                            error: join(field_errors(:password), ", ")
                          }),
                          box(:form_actions, [], [
                            button(:form_button, [type: "submit"], [text("Sign in")]),
                            link(:auth_secondary_link, [to: "/reset"], [
                              text("Forgot your password?")
                            ])
                          ])
                        ])
                      ]
                    ),
                    box(:auth_alternate, [], [
                      paragraph(:auth_alternate_text, [], [text("Or email me a sign-in link")]),
                      form(
                        :auth_form,
                        [
                          dom_id: "magic-link-form",
                          method: "post",
                          action: "/auth/user/magic_link/request"
                        ],
                        [
                          hidden(
                            :csrf_token,
                            [name: "_csrf_token", value: csrf_token],
                            []
                          ),
                          render(Tunez.UI.FormControl, %{
                            label: "Email",
                            dom_id: "magic-link-email",
                            hidden_label?: true,
                            control:
                              input(
                                :form_input,
                                [
                                  dom_id: "magic-link-email",
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
                          button(:primary_link_inverse, [type: "submit"], [
                            text("Send sign-in link")
                          ])
                        ]
                      )
                    ]),
                    paragraph(:auth_switch, [], [
                      text("Need an account? "),
                      link(:auth_secondary_link, [to: "/register"], [text("Register")])
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
      change set_attribute(:csrf_token, context(:csrf_token))
      change AshBlueprint.Changes.SetSessionId
      change Tunez.UI.Changes.BeginPageLife
    end

    update :edit do
      accept [:email, :password]
    end
  end
end
