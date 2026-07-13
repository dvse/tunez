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
    plug :protect_datastar_forms
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :mcp do
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/mcp" do
    pipe_through :mcp

    forward "/", AshAi.Mcp.Router,
      tools: [
        :tunez_lua_docs,
        :tunez_lua_eval
      ],
      otp_app: :tunez,
      mcp_name: "Tunez"
  end

  scope "/ds" do
    pipe_through :datastar

    forward "/", AshBlueprint.Datastar.Bridge,
      domains: [Tunez.UI],
      document: {__MODULE__, :datastar_document},
      session_id: {__MODULE__, :datastar_session_id, []},
      actor: &__MODULE__.datastar_actor/1,
      tenant: &__MODULE__.datastar_tenant/1,
      context: &__MODULE__.datastar_context/1
  end

  scope "/" do
    pipe_through :browser

    live_session :ash_blueprint,
      on_mount: [
        {__MODULE__, :blueprint_context},
        {AshBlueprint.Phoenix.LiveSession, :live_user_optional}
      ],
      session: {__MODULE__, :blueprint_session, []} do
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

  # Seed a protected form token on document GETs without changing Datastar's dispatch protocol.
  def protect_datastar_forms(%Plug.Conn{method: "GET"} = conn, _opts) do
    Plug.CSRFProtection.call(conn, Plug.CSRFProtection.init([]))
  end

  def protect_datastar_forms(conn, _opts), do: conn

  # The datastar document reuses the SAME shell as the LiveView pages —
  # document parity by construction. Scripts: the app bundle plus the
  # datastar runtime; never the LiveView runtime.
  def datastar_document(%{content: content, record: record, script_path: script_path}) do
    page_title =
      case Map.get(record, :page_title) do
        title when is_binary(title) ->
          title

        %Ash.NotLoaded{} ->
          case Ash.load(record, :page_title, authorize?: false) do
            {:ok, %{page_title: title}} when is_binary(title) -> title
            _other -> nil
          end

        _other ->
          nil
      end

    AshBlueprint.Phoenix.RootLayout.render(%{
      inner_content: {:safe, content},
      page_title: page_title,
      root_layout_scripts: [
        {script_path, "module"}
        | Application.get_env(:tunez, :root_layout_application_scripts, [])
      ]
    })
  end

  def blueprint_session(conn) do
    conn
    |> AshBlueprint.Phoenix.LiveSession.generate_session(:tunez)
    |> Map.put("csrf_token", Plug.CSRFProtection.get_csrf_token())
  end

  def on_mount(:blueprint_context, _params, session, socket) do
    context = %{csrf_token: Map.fetch!(session, "csrf_token")}
    {:cont, Phoenix.Component.assign(socket, :ash_blueprint_context, context)}
  end

  def datastar_actor(conn), do: conn.assigns[:current_user]

  def datastar_tenant(conn), do: Ash.PlugHelpers.get_tenant(conn)

  def datastar_context(conn) do
    conn
    |> Ash.PlugHelpers.get_context()
    |> Kernel.||(%{})
    |> Map.put(:csrf_token, Plug.CSRFProtection.get_csrf_token())
  end
end
