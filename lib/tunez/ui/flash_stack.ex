defmodule Tunez.UI.FlashStack do
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
    attribute :session_id, :uuid, allow_nil?: false, primary_key?: true, public?: true
    attribute :info, :string, public?: true
    attribute :error, :string, public?: true
    attribute :warning, :string, public?: true
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                box(:flash_group, [dom_id: "flash-group"], [
                  each(
                    [
                      %{dom_id: "flash-info", kind: :info, message: info},
                      %{dom_id: "flash-error", kind: :error, message: error},
                      %{dom_id: "flash-warning", kind: :warning, message: warning},
                      %{
                        dom_id: "client-error",
                        kind: :error,
                        message: "Attempting to reconnect",
                        title: "We can't find the internet",
                        hidden?: true,
                        spinner?: true
                      },
                      %{
                        dom_id: "server-error",
                        kind: :error,
                        message: "Hang in there while we get back on track",
                        title: "Something went wrong!",
                        hidden?: true,
                        spinner?: true
                      }
                    ],
                    :flash,
                    [key: flash.dom_id],
                    [
                      if is_nil(flash.message) do
                        nothing()
                      else
                        box(
                          :flash_message,
                          [
                            dom_id: flash.dom_id,
                            role: "alert",
                            hidden: flash.hidden?,
                            data: [kind: flash.kind],
                            on_click: :dismiss,
                            action_input: %{kind: flash.kind}
                          ],
                          [
                            box(:flash_grid, [], [
                              inline(:flash_kind_icon, [data: [kind: flash.kind]], []),
                              box(:flash_copy, [], [
                                if is_nil(flash.title) do
                                  nothing()
                                else
                                  paragraph(:flash_title, [], [text(flash.title)])
                                end,
                                paragraph(:flash_text, [], [
                                  text(flash.message),
                                  if flash.spinner? do
                                    inline(:flash_spinner, [], [])
                                  else
                                    nothing()
                                  end
                                ])
                              ]),
                              button(
                                :flash_close,
                                [
                                  type: "button",
                                  aria: [label: "close"]
                                ],
                                [inline(:flash_close_icon, [], [])]
                              )
                            ])
                          ]
                        )
                      end
                    ]
                  )
                ])
              )
  end

  identities do
    identity :session_instance, [:session_id], pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    create :mount do
      primary? true
      change AshBlueprint.Changes.SetSessionId
    end

    create :put_flash do
      argument :session_id, :uuid, allow_nil?: false
      argument :level, :atom, allow_nil?: false, constraints: [one_of: [:info, :error, :warning]]
      argument :message, :string, allow_nil?: false
      change set_attribute(:session_id, arg(:session_id))

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(
          changeset,
          Ash.Changeset.get_argument(changeset, :level),
          Ash.Changeset.get_argument(changeset, :message)
        )
      end
    end

    update :dismiss do
      argument :kind, :atom,
        allow_nil?: false,
        constraints: [one_of: [:info, :error, :warning]]

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(
          changeset,
          Ash.Changeset.get_argument(changeset, :kind),
          nil
        )
      end
    end
  end
end
