defmodule Tunez.UI.ArtistCard do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: :embedded,
    extensions: [AshBlueprint, AshLua.Resource],
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy action_type(:create) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :cover_image_url, :string, public?: true
    attribute :followed?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :follower_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :album_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :latest_album_year, :integer, public?: true
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr([
                box(:artist_card_image, [dom_id: "artist-" <> id, data: [role: "artist-card"]], [
                  link(:cover_link, [to: "/artists/" <> id], [
                    if followed? do
                      inline(:followed_icon, [], [])
                    else
                      nothing()
                    end,
                    render(Tunez.UI.CoverImage, %{image: cover_image_url})
                  ])
                ]),
                paragraph(:artist_card_heading, [], [
                  link(:artist_name, [to: "/artists/" <> id, data: [role: "artist-name"]], [
                    text(name)
                  ]),
                  if follower_count > 0 do
                    inline(:follower_count, [data: [role: "follower-count"]], [
                      inline(:follower_count_icon, [], []),
                      text(" "),
                      text(
                        if follower_count >= 1_000_000 do
                          to_string(round(follower_count / 1_000_000, 1)) <> "M"
                        else
                          if follower_count >= 1_000 do
                            to_string(round(follower_count / 1_000, 1)) <> "K"
                          else
                            to_string(follower_count)
                          end
                        end
                      )
                    ])
                  else
                    nothing()
                  end
                ]),
                if album_count > 0 do
                  inline(:artist_album_info, [], [
                    text(to_string(album_count)),
                    text(
                      if album_count == 1,
                        do: " album, latest release ",
                        else: " albums, latest release "
                    ),
                    text(to_string(latest_album_year))
                  ])
                else
                  nothing()
                end
              ])
  end

  actions do
    defaults create: :*
  end
end
