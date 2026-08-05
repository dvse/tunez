defmodule Tunez.Music.QueueControl do
  use Ash.Resource,
    domain: Tunez.Music,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshQueue.Resources.QueueControl, AshLua.Resource],
    validate_domain_inclusion?: false

  queue_resource do
    role(:queue_control)

    indexes([
      :control_kind_state_name,
      :control_kind_name,
      :control_kind_tenant_name,
      :control_kind_managed_by_seed_key,
      :control_kind_expires_at_key,
      :control_kind_inserted_at_key
    ])

    guarantees([:transactional_writes, :conditional_create, :conditional_update])
    attempts :embedded
    error_limit(20)
  end

  postgres do
    repo Tunez.Repo
    table "tunez_queue_controls"

    custom_indexes do
      index [:control_kind, :state, :name],
        name: "tunez_queue_controls_kind_state_name_idx"

      index [:control_kind, :name], name: "tunez_queue_controls_kind_name_idx"
      index [:control_kind, :tenant, :name], name: "tunez_queue_controls_kind_tenant_name_idx"

      index [:control_kind, :managed_by, :seed_key],
        name: "tunez_queue_controls_kind_managed_by_seed_key_idx"

      index [:control_kind, :expires_at, :key],
        name: "tunez_queue_controls_kind_expires_at_key_idx"

      index [:control_kind, :inserted_at, :key],
        name: "tunez_queue_controls_kind_inserted_at_key_idx"
    end
  end
end
