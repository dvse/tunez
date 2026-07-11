defmodule Tunez.UI.CoverImage do
  use Ash.Resource,
    data_layer: :embedded,
    extensions: [AshBlueprint],
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy action_type(:create) do
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
                if is_nil(image) do
                  box(:missing_cover, [], [inline(:missing_cover_icon, [], [])])
                else
                  image(:cover_image, [src: image], [])
                end
              )
  end

  actions do
    create :create do
      primary? true
      accept [:image]
    end
  end
end
