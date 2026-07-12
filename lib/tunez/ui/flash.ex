defmodule Tunez.UI.Flash do
  @moduledoc """
  One flash message per (session, kind), stamped with the page life it
  was put in. Visibility is a pure comparison against the session's
  page-life clock: a flash lives for the page life it was put in, plus
  one navigation when it rides a redirect (`carry?: true`) — exactly
  Phoenix flash semantics, as inspectable row state.
  """

  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: Ash.DataLayer.Ets,
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

    attribute :kind, :atom,
      allow_nil?: false,
      primary_key?: true,
      public?: true,
      constraints: [one_of: [:info, :error, :warning]]

    attribute :message, :string, allow_nil?: false, public?: true
    attribute :life, :integer, allow_nil?: false, default: 0, public?: true
    attribute :carry?, :boolean, allow_nil?: false, default: false, public?: true
  end

  relationships do
    has_one :page_life, Tunez.UI.PageLife do
      source_attribute :session_id
      destination_attribute :session_id
    end
  end

  calculations do
    # severity display order: info, error, warning (upstream flash-group order)
    calculate :rank,
              :integer,
              expr(if(kind == :info, do: 0, else: if(kind == :error, do: 1, else: 2))),
              public?: true

    calculate :visible?,
              :boolean,
              expr(life + if(carry?, do: 1, else: 0) >= (page_life.life || 0)),
              public?: true
  end

  identities do
    identity :session_kind, [:session_id, :kind], pre_check_with: Tunez.UI
  end

  actions do
    defaults [:read]

    create :put do
      description "Put or replace the session's flash of this kind, stamped with the current page life. carry?: true lets it ride one redirect."

      upsert? true
      upsert_identity :session_kind
      accept [:session_id, :kind, :message, :carry?]

      # registers the row for session GC (reads the accepted attribute)
      change AshBlueprint.Changes.SetSessionId

      change fn changeset, context ->
        life =
          case Tunez.UI.current_page_life(
                 Ash.Changeset.get_attribute(changeset, :session_id),
                 Ash.Scope.to_opts(context)
               ) do
            {:ok, %{life: life}} -> life
            _none -> 0
          end

        Ash.Changeset.change_attribute(changeset, :life, life)
      end
    end

    destroy :dismiss do
    end
  end
end
