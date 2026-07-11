defmodule Tunez.UI.AppShell do
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
    attribute :signed_in?, :boolean, allow_nil?: false, public?: true
    attribute :email, :string, allow_nil?: false, public?: true

    attribute :content, AshBlueprint.Type.RenderTree do
      allow_nil? false
      public? true
    end
  end

  calculations do
    calculate :view,
              AshBlueprint.Type.RenderTree,
              expr(
                box(:app_root, [], [
                  render(Tunez.UI.Navigation, %{
                    signed_in?: signed_in?,
                    email: email
                  }),
                  box(:app_content, [], [
                    render(Tunez.UI.FlashStack, %{}),
                    content
                  ])
                ])
              )
  end

  actions do
    create :create do
      primary? true
      accept [:signed_in?, :email, :content]
    end
  end
end
