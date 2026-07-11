defmodule TunezWeb.Router do
  use AshBlueprint.Phoenix.Router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :graphql do
    plug :load_from_bearer
    plug :set_actor, :user
    plug AshGraphql.Plug
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug AshBlueprint.Phoenix.EnsureSessionId
    plug :put_root_layout, html: {AshBlueprint.Phoenix.RootLayout, :render}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :datastar do
    plug :fetch_session
    plug AshBlueprint.Phoenix.EnsureSessionId
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/ds" do
    pipe_through :datastar

    forward "/", AshBlueprint.Datastar.Bridge,
      domains: [Tunez.UI],
      session_id: {__MODULE__, :datastar_session_id, []},
      actor: &__MODULE__.datastar_actor/1,
      tenant: &__MODULE__.datastar_tenant/1,
      context: &__MODULE__.datastar_context/1
  end

  scope "/" do
    pipe_through :browser

    live_session :ash_blueprint,
      on_mount: [
        {AshBlueprint.Phoenix.LiveSession, :live_user_optional}
      ],
      session: {AshBlueprint.Phoenix.LiveSession, :generate_session, [:tunez]} do
      ash_blueprint_routes(domains: [Tunez.UI])
    end
  end

  scope "/gql" do
    pipe_through [:graphql]

    forward "/playground", Absinthe.Plug.GraphiQL,
      schema: Module.concat(["TunezWeb.GraphqlSchema"]),
      socket: Module.concat(["TunezWeb.GraphqlSocket"]),
      interface: :simple

    forward "/", Absinthe.Plug, schema: Module.concat(["TunezWeb.GraphqlSchema"])
  end

  scope "/api/json" do
    pipe_through [:api]

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/json/open_api",
      default_model_expand_depth: 4

    forward "/", TunezWeb.AshJsonApiRouter
  end

  scope "/", TunezWeb do
    pipe_through :browser

    auth_routes AuthController, Tunez.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{TunezWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    TunezWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.Default
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  TunezWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.Default
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route Tunez.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [TunezWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Tunez.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [TunezWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.Default]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", TunezWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:tunez, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TunezWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  def datastar_session_id(conn),
    do: Plug.Conn.get_session(conn, "ash_blueprint_session_id")

  def datastar_actor(conn), do: conn.assigns[:current_user]

  def datastar_tenant(conn), do: Ash.PlugHelpers.get_tenant(conn)

  def datastar_context(conn), do: Ash.PlugHelpers.get_context(conn) || %{}
end
