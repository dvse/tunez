defmodule Tunez.Music.QueueKey do
  use Ash.Resource,
    domain: Tunez.Music,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshQueue.Resources.QueueKey, AshLua.Resource],
    validate_domain_inclusion?: false

  queue_resource do
    role(:queue_key)
    indexes([:job_id_key, :expires_at_key, :reservation_kind_expires_at_key])
    guarantees([:transactional_writes, :conditional_create, :conditional_update])
    transaction_group({:repo, Tunez.Repo})
    attempts :embedded
    error_limit(20)
  end

  postgres do
    repo Tunez.Repo
    table "tunez_queue_keys"

    custom_indexes do
      index [:job_id, :key], name: "tunez_queue_keys_job_id_key_idx"
      index [:expires_at, :key], name: "tunez_queue_keys_expires_at_key_idx"

      index [:reservation_kind, :expires_at, :key],
        name: "tunez_queue_keys_reservation_kind_expires_at_key_idx"
    end
  end
end
