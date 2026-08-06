defmodule TunezWeb do
  @moduledoc """
  The host web surface.

  Every screen is an AshBlueprint route, so there are no controllers, views,
  components, layouts, or LiveViews to configure here. What remains is host
  plumbing: the static asset paths the endpoint serves, and the verified-route
  helpers that host modules and email senders use to build links.

      use TunezWeb, :verified_routes
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: TunezWeb.Endpoint,
        router: TunezWeb.Router,
        statics: TunezWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate host helper.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
