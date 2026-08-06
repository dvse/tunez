defmodule Tunez.UI.Toast do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshLua.Resource],
    notifiers: [AshBlueprint.Notifier],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  resource do
    description """
    One transient notice per (session, severity). The row carries the instant
    it stops being shown; every read filters on that instant, so expiry is
    ordinary row state a reader can inspect and a test can assert. Dismissal
    deletes the row.
    """
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    attribute :session_id, :uuid, allow_nil?: false, primary_key?: true, public?: true

    attribute :severity, :atom,
      allow_nil?: false,
      primary_key?: true,
      public?: true,
      constraints: [one_of: [:info, :error, :warning]]

    attribute :message, :string, allow_nil?: false, public?: true
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :rank, :integer, allow_nil?: false, default: 0
  end

  identities do
    identity :session_severity, [:session_id, :severity], pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    read :live do
      description "The session's notices that have not expired yet."

      argument :session_id, :uuid do
        allow_nil? false
        public? true
      end

      filter expr(session_id == ^arg(:session_id) and expires_at > now())
    end

    create :put do
      description "Put or replace the session's notice of this severity. It stops showing after ttl_seconds."

      upsert? true
      upsert_identity :session_severity
      accept [:session_id, :severity, :message]

      argument :ttl_seconds, :integer do
        allow_nil? false
        default 10
        constraints min: 1, max: 3600
      end

      # registers the row for session GC (reads the accepted attribute)

      change set_attribute(:rank, 0) do
        where attribute_equals(:severity, :info)
      end

      change set_attribute(:rank, 1) do
        where attribute_equals(:severity, :error)
      end

      change set_attribute(:rank, 2) do
        where attribute_equals(:severity, :warning)
      end

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(
          changeset,
          :expires_at,
          DateTime.add(
            DateTime.utc_now(),
            Ash.Changeset.get_argument(changeset, :ttl_seconds),
            :second
          )
        )
      end
    end

    destroy :dismiss do
    end
  end
end
