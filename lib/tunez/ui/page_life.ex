defmodule Tunez.UI.PageLife do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshBlueprint, AshLua.Resource],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  resource do
    description """
    One row per UI session: the count of page mounts (navigations).

    This is the session's page-life clock. Flashes are stamped with the
    life they were put in and expire by pure integer comparison — see
    `Tunez.UI.Flash.visible?`. No aging writes and no app-authored lifecycle
    hooks: `Tunez.UI.Blueprint` supplies the clock contract to routed mounts
    through the compile-independent `Tunez.UI.PageLifeDomain` interface.
    """
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    attribute :session_id, :uuid, allow_nil?: false, primary_key?: true, public?: true
    attribute :life, :integer, allow_nil?: false, default: 0, public?: true
  end

  identities do
    identity :session_instance, [:session_id], pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    create :begin do
      upsert? true
      upsert_identity :session_instance

      argument :session_id, :uuid, allow_nil?: false
      change set_attribute(:session_id, arg(:session_id))
      # registers the row for session GC (falls through to the attribute)
      # first mount inserts at 1; remounts increment atomically against
      # the stored row (the atomic applies only on the conflict branch)
      change set_attribute(:life, 1)
      change atomic_update(:life, expr(life + 1))
    end
  end
end
