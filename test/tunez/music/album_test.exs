defmodule TunezWeb.Music.AlbumTest do
  use Tunez.DataCase, async: true

  alias Tunez.Accounts.Notification, warn: false
  alias Tunez.Music, warn: false

  describe "Tunez.Music.create_album/1-2" do
    test "stores the actor that created the record" do
      actor = generate(user(role: :admin))
      artist = generate(artist())

      album =
        Music.create_album!(
          %{name: "New Album", artist_id: artist.id, year_released: 2024},
          actor: actor
        )

      assert album.created_by_id == actor.id
      assert album.updated_by_id == actor.id
    end

    test "fans out one notification per follower through the queue trigger" do
      artist = generate(artist())
      actor = generate(user(role: :admin))
      followers = generate_many(user(), 3)
      _nonfollower = generate(user())

      Enum.each(followers, &Music.follow_artist!(artist, actor: &1))

      album =
        Music.create_album!(
          %{name: "New Album", artist_id: artist.id, year_released: 2024},
          actor: actor
        )

      assert [] = Ash.read!(Notification, authorize?: false)

      assert album =
               AshQueue.Test.assert_would_schedule(album, :fan_out_album_release_notifications)

      assert [_job] = AshQueue.Test.assert_triggered(album, :fan_out_album_release_notifications)

      assert {:ok, %{success: 1}} =
               AshQueue.Test.drain_queue(Tunez.Music, queue: :album_notifications)

      notifications = Ash.read!(Notification, authorize?: false)

      assert Enum.sort(Enum.map(notifications, & &1.user_id)) ==
               Enum.sort(Enum.map(followers, & &1.id))

      assert Enum.all?(notifications, &(&1.album_id == album.id))

      assert :ok =
               AshQueue.Test.refute_would_schedule(album, :fan_out_album_release_notifications)
    end

    test "the fan-out worker is structurally idempotent" do
      artist = generate(artist())
      actor = generate(user(role: :admin))
      followers = generate_many(user(), 3)
      Enum.each(followers, &Music.follow_artist!(artist, actor: &1))

      album =
        Music.create_album!(
          %{name: "Idempotent Album", artist_id: artist.id, year_released: 2024},
          actor: actor
        )

      for _run <- 1..2 do
        Ash.update!(album, %{},
          action: :fan_out_album_release_notifications,
          context: %{private: %{ash_queue?: true}},
          authorize?: true
        )
      end

      notifications = Ash.read!(Notification, authorize?: false)
      assert length(notifications) == length(followers)
      assert Enum.uniq_by(notifications, &{&1.album_id, &1.user_id}) == notifications
    end

    test "the template heals a follower added after the first fan-out" do
      artist = generate(artist())
      actor = generate(user(role: :admin))
      first_follower = generate(user())
      Music.follow_artist!(artist, actor: first_follower)

      album =
        Music.create_album!(
          %{name: "Healing Album", artist_id: artist.id, year_released: 2024},
          actor: actor
        )

      assert {:ok, %{success: 1}} =
               AshQueue.Test.drain_queue(Tunez.Music, queue: :album_notifications)

      assert :ok =
               AshQueue.Test.refute_would_schedule(album, :fan_out_album_release_notifications)

      late_follower = generate(user())
      Music.follow_artist!(artist, actor: late_follower)

      assert album =
               AshQueue.Test.assert_would_schedule(album, :fan_out_album_release_notifications)

      assert {:ok, _job} = AshQueue.Test.wake(album, :fan_out_album_release_notifications)

      assert {:ok, %{success: 1}} =
               AshQueue.Test.drain_queue(Tunez.Music, queue: :album_notifications)

      notifications = Ash.read!(Notification, authorize?: false)

      assert Enum.sort(Enum.map(notifications, & &1.user_id)) ==
               Enum.sort([first_follower.id, late_follower.id])
    end

    test "album creation does not write notifications inline" do
      artist = generate(artist())
      actor = generate(user(role: :admin))
      follower = generate(user())
      Music.follow_artist!(artist, actor: follower)

      album =
        Music.create_album!(
          %{name: "Queued Album", artist_id: artist.id, year_released: 2024},
          actor: actor
        )

      assert [] = Ash.read!(Notification, authorize?: false)
      assert [_job] = AshQueue.Test.assert_triggered(album, :fan_out_album_release_notifications)
    end
  end

  describe "Tunez.Music.update_album/2-3" do
    test "stores the actor that updated the record" do
      actor = generate(user(role: :admin))

      album = generate(album(name: "The Old Name"))
      refute album.updated_by_id == actor.id

      album = Music.update_album!(album, %{name: "The New Name"}, actor: actor)
      assert album.updated_by_id == actor.id
    end
  end

  describe "Tunez.Music.destroy_album/1-2" do
    test "deletes any notifications about the album" do
      editor = generate(user(role: :editor))
      album = generate(album(actor: editor))
      %{id: to_stay_id} = generate(notification())
      _to_go = generate(notification(album_id: album.id))

      Music.destroy_album!(album, actor: editor)

      notifications = Ash.read!(Tunez.Accounts.Notification, authorize?: false)

      assert length(notifications) == 1
      assert Enum.map(notifications, & &1.id) == [to_stay_id]
    end

    test "deletes the notification through the resource notifier path" do
      follower = generate(user())
      album = generate(album())
      %{id: notification_id} = generate(notification(album_id: album.id, user_id: follower.id))
      Music.destroy_album!(album, authorize?: false)

      assert {:error, _error} = Ash.get(Tunez.Accounts.Notification, notification_id)
    end
  end

  describe "policies" do
    def setup_users do
      %{
        admin: generate(user(role: :admin)),
        editor: generate(user(role: :editor)),
        user: generate(user(role: :user))
      }
    end

    test "admins and editors can create new albums" do
      users = setup_users()
      assert Music.can_create_album?(users.admin)
      assert Music.can_create_album?(users.editor)
      refute Music.can_create_album?(users.user)
      refute Music.can_create_album?(nil)
    end

    test "admins can delete albums" do
      users = setup_users()
      album = generate(album())

      assert Music.can_destroy_album?(users.admin, album)
      refute Music.can_destroy_album?(users.user, album)
      refute Music.can_destroy_album?(nil, album)
    end

    test "admins can update albums" do
      users = setup_users()
      album = generate(album())

      assert Music.can_update_album?(users.admin, album)
      refute Music.can_update_album?(users.user, album)
      refute Music.can_update_album?(nil, album)
    end

    test "editors can edit albums that they created" do
      users = setup_users()
      can_edit = generate(album(seed?: true, created_by: users.editor))
      cant_edit = generate(album(seed?: true, created_by: users.admin))

      assert Music.can_update_album?(users.editor, can_edit)
      refute Music.can_update_album?(users.editor, cant_edit)
    end

    test "editors can delete albums that they created" do
      users = setup_users()
      can_delete = generate(album(seed?: true, created_by: users.editor))
      cant_delete = generate(album(seed?: true, created_by: users.admin))

      assert Music.can_destroy_album?(users.editor, can_delete)
      refute Music.can_destroy_album?(users.editor, cant_delete)
    end
  end

  describe "validations" do
    test "year_released must be between 1950 and next year" do
      admin = generate(user(role: :admin))
      artist = generate(artist())

      # The assertion isn't really needed here, but we want to signal to
      # our future selves that this is part of the test, not the setup.
      assert %{artist_id: artist.id, name: "test 2024", year_released: 2024}
             |> Music.create_album!(actor: admin)

      # Using `assert_raise`
      assert_raise Ash.Error.Invalid, ~r/must be between 1950 and next year/, fn ->
        %{artist_id: artist.id, name: "test 1925", year_released: 1925}
        |> Music.create_album!(actor: admin)
      end

      # Using `assert_has_error` - note the lack of bang to return the error
      %{artist_id: artist.id, name: "test 1950", year_released: 1950}
      |> Music.create_album(actor: admin)
      |> Ash.Test.assert_has_error(Ash.Error.Invalid, fn error ->
        match?(%{message: "must be between 1950 and next year"}, error)
      end)
    end

    test "cover_image_url must be either a remote URL or a local URL from /images" do
      admin = generate(user(role: :admin))
      artist = generate(artist())

      with_url = fn url ->
        Ash.Generator.action_input(Tunez.Music.Album, :create,
          artist_id: artist.id,
          year_released: 2025,
          tracks: [],
          cover_image_url: url
        )
        |> Enum.at(0)
      end

      assert Music.create_album!(with_url.("/images/test.jpg"), actor: admin)

      assert_raise Ash.Error.Invalid, ~r/must start with/, fn ->
        Music.create_album!(with_url.("notavalidURL"), actor: admin)
      end

      with_url.("/image/tunez.mp3")
      |> Music.create_album(actor: admin)
      |> assert_has_error(fn error ->
        error.field == :cover_image_url && error.message == "must start with https:// or /images/"
      end)
    end
  end
end
