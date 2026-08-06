defmodule Tunez.UI.ToastStack do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint, AshLua.Resource],
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
    # The filter IS the expiry: a notice shows while its own row says it is
    # still current, and stops showing when the row says it is not.
    has_many :toasts, Tunez.UI.Toast do
      source_attribute :session_id
      destination_attribute :session_id
      filter expr(expires_at > now())
      sort rank: :asc
      public? true
    end
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                box(:toast_group, [dom_id: "toast-group"], [
                  # the failure notice IS the dispatch's fieldless error —
                  # a per-dispatch transient, cleared by the next
                  # successful dispatch
                  if is_nil(path(find_by(errors(), [:field], nil), [:message])) do
                    nothing()
                  else
                    box(
                      :toast_message,
                      [
                        dom_id: "toast-error",
                        role: "alert",
                        data: [severity: :error],
                        on_click: :dismiss,
                        action_input: %{severity: :error}
                      ],
                      [
                        box(:toast_grid, [], [
                          inline(
                            :toast_severity_icon,
                            [data: %{severity: :error, icon: "error"}],
                            []
                          ),
                          box(:toast_copy, [], [
                            paragraph(:toast_text, [], [
                              text(path(find_by(errors(), [:field], nil), [:message]))
                            ])
                          ]),
                          button(
                            :toast_close,
                            [type: "button", aria: [label: "close"]],
                            [inline(:toast_close_icon, [data: %{icon: "close"}], [])]
                          )
                        ])
                      ]
                    )
                  end,
                  each(toasts, :toast, [key: toast.severity], [
                    box(
                      :toast_message,
                      [
                        dom_id: "toast-" <> to_string(toast.severity),
                        role: "alert",
                        data: [severity: toast.severity],
                        on_click: :dismiss,
                        action_input: %{severity: toast.severity}
                      ],
                      [
                        box(:toast_grid, [], [
                          inline(
                            :toast_severity_icon,
                            [
                              data: %{
                                severity: toast.severity,
                                icon:
                                  if toast.severity == :info do
                                    "pass-filled"
                                  else
                                    if toast.severity == :error do
                                      "error"
                                    else
                                      "warning"
                                    end
                                  end
                              }
                            ],
                            []
                          ),
                          box(:toast_copy, [], [
                            paragraph(:toast_text, [], [text(toast.message)])
                          ]),
                          button(
                            :toast_close,
                            [type: "button", aria: [label: "close"]],
                            [inline(:toast_close_icon, [data: %{icon: "close"}], [])]
                          )
                        ])
                      ]
                    )
                  ]),
                  box(
                    :toast_message,
                    [
                      dom_id: "client-error",
                      role: "alert",
                      hidden: true,
                      data: [severity: :error]
                    ],
                    [
                      box(:toast_grid, [], [
                        inline(
                          :toast_severity_icon,
                          [data: %{severity: :error, icon: "error"}],
                          []
                        ),
                        box(:toast_copy, [], [
                          paragraph(:toast_title, [], [text("We can't find the internet")]),
                          paragraph(:toast_text, [], [
                            text("Attempting to reconnect"),
                            inline(:toast_spinner, [data: %{icon: "loading"}], [])
                          ])
                        ]),
                        button(
                          :toast_close,
                          [type: "button", aria: [label: "close"]],
                          [inline(:toast_close_icon, [data: %{icon: "close"}], [])]
                        )
                      ])
                    ]
                  ),
                  box(
                    :toast_message,
                    [
                      dom_id: "server-error",
                      role: "alert",
                      hidden: true,
                      data: [severity: :error]
                    ],
                    [
                      box(:toast_grid, [], [
                        inline(
                          :toast_severity_icon,
                          [data: %{severity: :error, icon: "error"}],
                          []
                        ),
                        box(:toast_copy, [], [
                          paragraph(:toast_title, [], [text("Something went wrong!")]),
                          paragraph(:toast_text, [], [
                            text("Hang in there while we get back on track"),
                            inline(:toast_spinner, [data: %{icon: "loading"}], [])
                          ])
                        ]),
                        button(
                          :toast_close,
                          [type: "button", aria: [label: "close"]],
                          [inline(:toast_close_icon, [data: %{icon: "close"}], [])]
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

    read :for_session do
      description "Read the visible notice state for one browser session."

      argument :session_id, :uuid do
        allow_nil? false
        public? true
      end

      filter expr(session_id == ^arg(:session_id))
    end

    create :mount do
      primary? true
      upsert? true
      upsert_identity :session_instance
    end

    update :dismiss do
      require_atomic? false

      argument :severity, :atom,
        allow_nil?: false,
        public?: true,
        constraints: [one_of: [:info, :error, :warning]]

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          case Tunez.UI.dismiss_toast(
                 changeset.data.session_id,
                 Ash.Changeset.get_argument(changeset, :severity),
                 Ash.Scope.to_opts(context)
               ) do
            :ok -> changeset
            # transient error notices have no row: the dismiss dispatch
            # itself clears the error transients they render from
            {:error, _not_found} -> changeset
          end
        end)
      end
    end
  end
end
