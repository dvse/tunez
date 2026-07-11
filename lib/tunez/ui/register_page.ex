defmodule Tunez.UI.RegisterPage do
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
    route "/register"
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
    calculate :page_title, :string, expr("Register"), public?: true

    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                render(Tunez.UI.AppShell, %{
                  signed_in?: false,
                  email: "",
                  content: [
                    heading(:page_h1, [level: 1], [text("Register")]),
                    form(
                      :auth_form,
                      [
                        dom_id: "register-form",
                        method: "post",
                        action: "/auth/user/password/register"
                      ],
                      [
                        hidden(:csrf_token, [name: "_csrf_token", value: csrf_token], []),
                        box(:form_stack, [], [
                          render(Tunez.UI.FormControl, %{
                            label: "Email",
                            dom_id: "register-email",
                            control:
                              input(
                                :form_input,
                                [
                                  dom_id: "register-email",
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
                            dom_id: "register-password",
                            control:
                              input(
                                :form_input,
                                [
                                  dom_id: "register-password",
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
                            dom_id: "register-password-confirmation",
                            control:
                              input(
                                :form_input,
                                [
                                  dom_id: "register-password-confirmation",
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
                            button(:form_button, [type: "submit"], [text("Register")])
                          ])
                        ])
                      ]
                    ),
                    paragraph(:auth_switch, [], [
                      text("Already have an account? "),
                      link(:auth_secondary_link, [to: "/sign-in"], [text("Sign in")])
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
      change AshBlueprint.Changes.SetSessionId
    end

    update :edit do
      accept [:email, :password, :password_confirmation]
      validate confirm(:password, :password_confirmation)
    end
  end
end
