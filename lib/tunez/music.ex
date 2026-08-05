defmodule Tunez.Music do
  use Ash.Domain,
    otp_app: :tunez,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain, AshPhoenix, AshLua.Domain, AshAi]

  graphql do
    queries do
      get Tunez.Music.Artist, :get_artist_by_id, :read
      list Tunez.Music.Artist, :search_artists, :search
    end

    mutations do
      create Tunez.Music.Artist, :create_artist, :create
      update Tunez.Music.Artist, :update_artist, :update
      destroy Tunez.Music.Artist, :destroy_artist, :destroy
      create Tunez.Music.ArtistFollower, :follow_artist, :create

      create Tunez.Music.Album, :create_album, :create
      update Tunez.Music.Album, :update_album, :update
      destroy Tunez.Music.Album, :destroy_album, :destroy
    end
  end

  json_api do
    routes do
      base_route "/artists", Tunez.Music.Artist do
        get :read
        index :search
        post :create
        patch :update
        delete :destroy
        related :albums, :read, primary?: true
      end

      base_route "/albums", Tunez.Music.Album do
        post :create
        patch :update
        delete :destroy
      end
    end
  end

  forms do
    form :create_album, args: [:artist_id]
  end

  lua do
    namespace "music.artist" do
      action :read, Tunez.Music.Artist, :read
      action :search, Tunez.Music.Artist, :search
      action :browse, Tunez.Music.Artist, :browse
      action :create, Tunez.Music.Artist, :create
      action :update, Tunez.Music.Artist, :update
      action :follow, Tunez.Music.Artist, :follow
      action :unfollow, Tunez.Music.Artist, :unfollow
      action :destroy, Tunez.Music.Artist, :destroy
    end

    namespace "music.album" do
      action :read, Tunez.Music.Album, :read
      action :create, Tunez.Music.Album, :create
      action :update, Tunez.Music.Album, :update
      action :upload_cover, Tunez.Music.Album, :upload_cover
      action :destroy, Tunez.Music.Album, :destroy
    end

    namespace "music.track" do
      action :read, Tunez.Music.Track, :read
    end

    namespace "music.artist_follower" do
      action :read, Tunez.Music.ArtistFollower, :read
      action :for_artist, Tunez.Music.ArtistFollower, :for_artist
      action :create, Tunez.Music.ArtistFollower, :create
      action :unfollow, Tunez.Music.ArtistFollower, :unfollow
    end
  end

  resources do
    resource Tunez.Music.Artist do
      define :create_artist, action: :create
      define :read_artists, action: :read

      define :browse_artists,
        action: :browse,
        args: [:query],
        default_options: [
          load: [
            :follower_count,
            :followed_by_me,
            :album_count,
            :latest_album_year_released,
            :cover_image_url
          ]
        ]

      define :search_artists,
        action: :search,
        args: [:query],
        default_options: [
          load: [
            :follower_count,
            :followed_by_me,
            :album_count,
            :latest_album_year_released,
            :cover_image_url
          ]
        ]

      define :get_artist_by_id, action: :read, get_by: :id
      define :update_artist, action: :update
      define :follow_artist_by_id, action: :follow, get_by: :id
      define :unfollow_artist_by_id, action: :unfollow, get_by: :id
      define :destroy_artist, action: :destroy
    end

    resource Tunez.Music.Album do
      define :create_album, action: :create
      define :get_album_by_id, action: :read, get_by: :id
      define :get_manageable_album_by_id, action: :manageable, get_by: :id
      define :update_album, action: :update
      define :upload_album_cover, action: :upload_cover
      define :destroy_album, action: :destroy
    end

    resource Tunez.Music.Track

    resource Tunez.Music.ArtistFollower do
      define :follow_artist do
        action :create
        args [:artist]

        custom_input :artist, :struct do
          constraints instance_of: Tunez.Music.Artist
          transform to: :artist_id, using: & &1.id
        end
      end

      define :unfollow_artist do
        action :destroy
        args [:artist]
        get? true

        custom_input :artist, :struct do
          constraints instance_of: Tunez.Music.Artist
          transform to: :artist_id, using: & &1.id
        end
      end

      define :followers_for_artist, action: :for_artist, args: [:artist_id]
    end
  end
end
