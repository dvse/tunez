defmodule Tunez.Music.Queue do
  use Ash.Resource,
    domain: Tunez.Music,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshQueue.Resources.Queue, AshLua.Resource],
    validate_domain_inclusion?: false

  queue_resource do
    role(:queue)

    indexes([
      :queue_state_priority_scheduled_id,
      :state_scheduled_id,
      :state_attempted_id,
      :state_expires_id,
      :queue_state_scheduled_id,
      :queue_state_attempted_id,
      :queue_state_expires_id,
      :tenant_queue_state_priority_scheduled_id
    ])

    claim_current_record_guards([:queue, :state_available, :attempts_remaining, :scheduled_due])
    guarantees([:transactional_writes, :conditional_create, :conditional_update])
    transaction_group({:repo, Tunez.Repo})
    transactional_enqueue?(true)
    claim_mode(:atomic_update)
    attempts :embedded
    error_limit(20)
  end

  postgres do
    repo Tunez.Repo
    table "tunez_queue_jobs"

    custom_indexes do
      index [:queue, :state, :priority, :scheduled_at, :id],
        name: "tunez_queue_jobs_queue_state_priority_scheduled_id_idx"

      index [:state, :scheduled_at, :id],
        name: "tunez_queue_jobs_state_scheduled_id_idx"

      index [:state, :attempted_at, :id],
        name: "tunez_queue_jobs_state_attempted_id_idx"

      index [:state, :expires_at, :id],
        name: "tunez_queue_jobs_state_expires_id_idx"

      index [:queue, :state, :scheduled_at, :id],
        name: "tunez_queue_jobs_queue_state_scheduled_id_idx"

      index [:queue, :state, :attempted_at, :id],
        name: "tunez_queue_jobs_queue_state_attempted_id_idx"

      index [:queue, :state, :expires_at, :id],
        name: "tunez_queue_jobs_queue_state_expires_id_idx"

      index [:tenant, :queue, :state, :priority, :scheduled_at, :id],
        name: "tunez_queue_jobs_tenant_queue_state_priority_scheduled_id_idx"
    end
  end
end
