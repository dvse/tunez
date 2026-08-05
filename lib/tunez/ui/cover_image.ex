defmodule Tunez.UI.CoverImage do
  use Ash.Resource,
    domain: Tunez.UI,
    data_layer: :embedded,
    extensions: [AshBlueprint, Tunez.UI.Blueprint, AshLua.Resource],
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    attribute :image, :string, public?: true
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                if image do
                  image(:cover_image, [src: image], [])
                else
                  box(:missing_cover, [], [
                    inline(:missing_cover_icon, [data: %{icon: "file-media"}], [])
                  ])
                end
              )
  end

  actions do
    defaults create: :*
  end
end
