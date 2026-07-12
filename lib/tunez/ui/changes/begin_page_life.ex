defmodule Tunez.UI.Changes.BeginPageLife do
  @moduledoc """
  Declares that mounting this page begins a new page life for its
  session: the session's `Tunez.UI.PageLife` clock ticks, and flashes
  from earlier page lives expire (see `Tunez.UI.Flash`). Every routed
  page's `:mount` declares this; child resources (shell, header, flash
  stack) do not.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    # a :static mount is the first half of one navigation (the live
    # attach re-runs it) — the clock ticks once, on the effective mount
    if changeset.context[:ash_blueprint_mount_phase] == :static do
      changeset
    else
      tick(changeset, context)
    end
  end

  defp tick(changeset, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      session_id =
        Ash.Changeset.get_attribute(changeset, :session_id) || changeset.data.session_id

      {:ok, _life} = Tunez.UI.begin_page_life(session_id, Ash.Scope.to_opts(context))
      changeset
    end)
  end
end
