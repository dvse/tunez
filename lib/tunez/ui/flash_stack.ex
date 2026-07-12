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
  end

  relationships do
    # visible? IS the whole Phoenix flash lifecycle: a pure comparison of
    # the flash's stamped page life against the session's page-life clock
    has_many :flashes, Tunez.UI.Flash do
      source_attribute :session_id
      destination_attribute :session_id
      sort rank: :asc
    end
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                box(:flash_group, [dom_id: "flash-group"], [
                  # the failure flash IS the dispatch's fieldless error —
                  # a per-dispatch transient, cleared by the next
                  # successful dispatch (exactly LiveView's lifecycle)
                  if is_nil(path(find_by(errors(), [:field], nil), [:message])) do
                    nothing()
                  else
                    box(
                      :flash_message,
                      [
                        dom_id: "flash-error",
                        role: "alert",
                        data: [kind: :error],
                        on_click: :dismiss,
                        action_input: %{kind: :error}
                      ],
                      [
                        box(:flash_grid, [], [
                          inline(:flash_kind_icon, [data: [kind: :error]], []),
                          box(:flash_copy, [], [
                            paragraph(:flash_text, [], [
                              text(path(find_by(errors(), [:field], nil), [:message]))
                            ])
                          ]),
                          button(
                            :flash_close,
                            [type: "button", aria: [label: "close"]],
                            [inline(:flash_close_icon, [], [])]
                          )
                        ])
                      ]
                    )
                  end,
                  each(flashes, :flash, [key: flash.kind], [
                    if flash.visible? do
                      box(
                        :flash_message,
                        [
                          dom_id: "flash-" <> to_string(flash.kind),
                          role: "alert",
                          data: [kind: flash.kind],
                          on_click: :dismiss,
                          action_input: %{kind: flash.kind}
                        ],
                        [
                          box(:flash_grid, [], [
                            inline(:flash_kind_icon, [data: [kind: flash.kind]], []),
                            box(:flash_copy, [], [
                              paragraph(:flash_text, [], [text(flash.message)])
                            ]),
                            button(
                              :flash_close,
                              [type: "button", aria: [label: "close"]],
                              [inline(:flash_close_icon, [], [])]
                            )
                          ])
                        ]
                      )
                    else
                      nothing()
                    end
                  ]),
                  box(
                    :flash_message,
                    [dom_id: "client-error", role: "alert", hidden: true, data: [kind: :error]],
                    [
                      box(:flash_grid, [], [
                        inline(:flash_kind_icon, [data: [kind: :error]], []),
                        box(:flash_copy, [], [
                          paragraph(:flash_title, [], [text("We can't find the internet")]),
                          paragraph(:flash_text, [], [
                            text("Attempting to reconnect"),
                            inline(:flash_spinner, [], [])
                          ])
                        ]),
                        button(
                          :flash_close,
                          [type: "button", aria: [label: "close"]],
                          [inline(:flash_close_icon, [], [])]
                        )
                      ])
                    ]
                  ),
                  box(
                    :flash_message,
                    [dom_id: "server-error", role: "alert", hidden: true, data: [kind: :error]],
                    [
                      box(:flash_grid, [], [
                        inline(:flash_kind_icon, [data: [kind: :error]], []),
                        box(:flash_copy, [], [
                          paragraph(:flash_title, [], [text("Something went wrong!")]),
                          paragraph(:flash_text, [], [
                            text("Hang in there while we get back on track"),
                            inline(:flash_spinner, [], [])
                          ])
                        ]),
                        button(
                          :flash_close,
                          [type: "button", aria: [label: "close"]],
                          [inline(:flash_close_icon, [], [])]
                        )
                      ])
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
      upsert? true
      upsert_identity :session_instance
      change AshBlueprint.Changes.SetSessionId
    end

    update :dismiss do
      require_atomic? false

      argument :kind, :atom,
        allow_nil?: false,
        constraints: [one_of: [:info, :error, :warning]]

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          case Tunez.UI.dismiss_flash(
                 changeset.data.session_id,
                 Ash.Changeset.get_argument(changeset, :kind),
                 Ash.Scope.to_opts(context)
               ) do
            :ok -> changeset
            # transient error flashes have no row: the dismiss dispatch
            # itself clears the error transients they render from
            {:error, _not_found} -> changeset
          end
        end)
      end
    end
  end
end
