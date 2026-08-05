defmodule Tunez.Music.TrackTest do
  use Tunez.DataCase, async: true

  alias Tunez.Music, warn: false

  test "public contracts expose stored order and duration seconds" do
    assert AshJsonApi.Resource.Info.default_fields(Music.Track) == [
             :order,
             :name,
             :duration_seconds
           ]

    assert Ash.Resource.Info.attribute(Music.Track, :order).public?
    assert Ash.Resource.Info.attribute(Music.Track, :duration_seconds).public?
    assert Ash.Resource.Info.aggregate(Music.Album, :duration_seconds).public?
    refute Ash.Resource.Info.calculation(Music.Track, :number)
    refute Ash.Resource.Info.calculation(Music.Track, :duration)
    refute Ash.Resource.Info.calculation(Music.Album, :duration)
  end

  describe "policies" do
    test "anyone can read track records" do
      track = generate(track(seed?: true))
      assert Ash.can?({Music.Track, :read}, nil, data: track)
    end

    test "track records can't be updated unless through the Album resource" do
      admin = generate(user(role: :admin))

      album = generate(album())
      track = generate(track(seed?: true, album_id: album.id))

      refute Ash.can?({track, :update}, admin)

      # Assert that an update through the album can succeed, and update the
      # data in the database
      updated_album =
        Music.update_album!(
          album,
          %{tracks: [%{name: "new!!", duration: "2:22"}]},
          actor: admin
        )

      updated_track = Ash.load!(updated_album, [:tracks]) |> Map.get(:tracks) |> List.first()
      assert updated_track.name == "new!!"
    end
  end
end
