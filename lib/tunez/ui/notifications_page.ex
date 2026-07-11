defmodule Tunez.UI.NotificationsPage do
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
      authorize_if actor_present()
    end
  end

  attributes do
    attribute :session_id, :uuid, allow_nil?: false, primary_key?: true, public?: false
    attribute :open?, :boolean, allow_nil?: false, default: false
  end

  relationships do
    has_many :notifications, Tunez.Accounts.Notification do
      no_attributes? true
      read_action :for_user
    end
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                box(:notifications_container, [dom_id: "notifications_container"], [
                  box(:notifications_root, [], [
                    box(
                      :notifications_toggle,
                      [tabindex: 0, on_click: :toggle, on_click_away: :close],
                      [
                        inline(:notifications_bell_icon, [], []),
                        if empty?(notifications) do
                          nothing()
                        else
                          inline(:notifications_badge, [], [
                            inline(:notifications_badge_ping, [], []),
                            inline(:notifications_badge_dot, [], [])
                          ])
                        end
                      ]
                    ),
                    box(
                      :notifications_panel,
                      [
                        dom_id: "notifications",
                        state: [open: open?]
                      ],
                      [
                        if empty?(notifications) do
                          box(:notifications_empty, [], [
                            inline(:notifications_empty_icon, [], []),
                            inline(:notifications_empty_text, [], [text("No new notifications!")])
                          ])
                        else
                          list(:notification_list, [tabindex: 0], [
                            each(notifications, :notification, [key: notification.id], [
                              item(:notification_item, [], [
                                link(
                                  :notification_item_link,
                                  [
                                    to:
                                      "/artists/" <>
                                        notification.album.artist_id <>
                                        "/#album-" <>
                                        notification.album_id,
                                    on_click: :dismiss,
                                    action_input: %{notification_id: notification.id}
                                  ],
                                  [
                                    paragraph(:notification_copy, [], [
                                      text("The album "),
                                      inline(:notification_album, [], [
                                        text(notification.album.name)
                                      ]),
                                      text(" has been added for "),
                                      text(notification.album.artist.name),
                                      break(:notification_break, [], []),
                                      inline(:notification_time, [], [
                                        text(time_ago_in_words(notification.inserted_at))
                                      ])
                                    ]),
                                    box(:notification_cover, [], [
                                      render(Tunez.UI.CoverImage, %{
                                        image: notification.album.cover_image_url
                                      })
                                    ])
                                  ]
                                )
                              ])
                            ])
                          ])
                        end
                      ]
                    )
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
      change AshBlueprint.Changes.SetSessionId
    end

    update :toggle do
      change atomic_update(:open?, expr(not open?))
    end

    update :close do
      change set_attribute(:open?, false)
    end

    update :dismiss do
      require_atomic? false
      argument :notification_id, :uuid, allow_nil?: false

      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          notification =
            Enum.find(
              changeset.data.notifications,
              &(&1.id == Ash.Changeset.get_argument(changeset, :notification_id))
            )

          :ok = Tunez.Accounts.dismiss_notification(notification, scope: context)
          Ash.Changeset.force_change_attribute(changeset, :open?, false)
        end)
      end
    end
  end
end
