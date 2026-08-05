defmodule Tunez.Music.Cron do
  use Ash.Resource,
    domain: Tunez.Music,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshQueue.Resources.Cron, AshLua.Resource],
    validate_domain_inclusion?: false

  queue_resource do
    role(:cron)
    indexes([:state_next_run_at_id, :queue_state_next_run_at_id, :managed_by_seed_key])
    guarantees([:transactional_writes, :conditional_create, :conditional_update])
    attempts :embedded
    error_limit(20)
  end

  postgres do
    repo Tunez.Repo
    table "tunez_queue_schedules"

    custom_indexes do
      index [:state, :next_run_at, :id],
        name: "tunez_queue_schedules_state_next_run_at_id_idx"

      index [:queue, :state, :next_run_at, :id],
        name: "tunez_queue_schedules_queue_state_next_run_at_id_idx"

      index [:managed_by, :seed_key],
        name: "tunez_queue_schedules_managed_by_seed_key_idx"
    end
  end
end
