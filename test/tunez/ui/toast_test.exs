defmodule Tunez.UI.ToastTest do
  use Tunez.DataCase, async: true

  require Ash.Query

  # A notice is a row. It shows while its own row says it is current, it stops
  # showing when the row says it is not, and dismissing it deletes the row.
  # There is no clock, no counter, and no mount hook anywhere in these tests.

  setup do
    session_id = Ash.UUID.generate()
    {:ok, _stack} = mount_stack(session_id)
    %{session_id: session_id}
  end

  test "a notice appears in the session's stack", %{session_id: session_id} do
    {:ok, toast} = Tunez.UI.put_toast(session_id, :info, "Artist saved successfully")

    assert toast.severity == :info
    assert toast.message == "Artist saved successfully"
    assert DateTime.after?(toast.expires_at, DateTime.utc_now())

    assert ["Artist saved successfully"] = stack_messages(session_id)
  end

  test "a notice stays visible for its own window", %{session_id: session_id} do
    {:ok, _toast} =
      Tunez.UI.put_toast(session_id, :info, "Still current", %{ttl_seconds: 3600})

    assert ["Still current"] = stack_messages(session_id)
    assert [%{message: "Still current"}] = Tunez.UI.live_toasts!(session_id)
  end

  test "an expired notice is filtered out of the read", %{session_id: session_id} do
    Ash.Seed.seed!(Tunez.UI.Toast, %{
      session_id: session_id,
      severity: :warning,
      message: "Expired notice",
      expires_at: DateTime.add(DateTime.utc_now(), -1, :second),
      rank: 2
    })

    {:ok, _live} = Tunez.UI.put_toast(session_id, :info, "Live notice")

    # both rows are still stored; the read is what decides
    assert session_rows(session_id) == ["Expired notice", "Live notice"]

    assert ["Live notice"] = stack_messages(session_id)
    assert [%{message: "Live notice"}] = Tunez.UI.live_toasts!(session_id)
  end

  test "dismissing a notice deletes its row", %{session_id: session_id} do
    {:ok, _toast} = Tunez.UI.put_toast(session_id, :info, "Dismiss me")
    assert ["Dismiss me"] = stack_messages(session_id)

    :ok = Tunez.UI.dismiss_toast(session_id, :info)

    assert [] = stack_messages(session_id)
    assert session_rows(session_id) == []
  end

  test "a second notice of the same severity replaces the first", %{session_id: session_id} do
    {:ok, _first} = Tunez.UI.put_toast(session_id, :info, "First")
    {:ok, _second} = Tunez.UI.put_toast(session_id, :info, "Second")

    assert ["Second"] = stack_messages(session_id)
  end

  defp mount_stack(session_id) do
    Tunez.UI.ToastStack
    |> Ash.Changeset.for_create(:mount, %{},
      context: %{session_id: session_id},
      domain: Tunez.UI,
      upsert?: true,
      upsert_identity: :session_instance
    )
    |> Ash.create(domain: Tunez.UI)
  end

  defp session_rows(session_id) do
    Tunez.UI.Toast
    |> Ash.Query.filter(session_id == ^session_id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.message)
    |> Enum.sort()
  end

  defp stack_messages(session_id) do
    [stack] =
      Tunez.UI.ToastStack
      |> Ash.Query.for_read(:for_session, %{session_id: session_id})
      |> Ash.read!()

    stack
    |> Ash.load!(:toasts)
    |> Map.fetch!(:toasts)
    |> Enum.map(& &1.message)
  end
end
