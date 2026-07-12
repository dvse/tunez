# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash_graphql, authorize_update_destroy_with_error?: true

config :mime,
  extensions: %{"json" => "application/vnd.api+json"},
  types: %{"application/vnd.api+json" => ["json"]}

config :ash_json_api,
  show_public_calculations_when_loaded?: false,
  authorize_update_destroy_with_error?: true

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec],
  custom_expressions: [
    AshBlueprint.Expressions.ToString,
    AshBlueprint.Expressions.Humanize,
    AshBlueprint.Expressions.RelativeTime,
    AshBlueprint.Expressions.TimeAgoInWords,
    AshBlueprint.Expressions.Truncate,
    AshBlueprint.Expressions.StripPrefix,
    AshBlueprint.Expressions.ClassJoin
  ]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :authentication,
        :token,
        :user_identity,
        :graphql,
        :json_api,
        :postgres,
        :resource,
        :code_interface,
        :policies,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :actions,
        :multitenancy
      ]
    ],
    "Ash.Domain": [
      section_order: [
        :graphql,
        :json_api,
        :resources,
        :policies,
        :authorization,
        :domain,
        :execution
      ]
    ]
  ]

config :tunez,
  ecto_repos: [Tunez.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [Tunez.Accounts, Tunez.Music, Tunez.UI],
  ash_authentication: [return_error_on_invalid_magic_link_token?: true]

config :tunez,
  root_layout_stylesheets: ["/assets/app.css"],
  root_layout_application_scripts: [{"/assets/app.js", "module"}],
  root_layout_html_attributes: [lang: "en", class: "min-h-full"],
  root_layout_body_attributes: [class: "min-h-full antialiased mb-4"],
  root_layout_ui_zoom: nil,
  root_layout_default_title: "Hello!",
  root_layout_title_suffix: " · Tunez"

config :ash_blueprint_phoenix, otp_app: :tunez

# Configures the endpoint
config :tunez, TunezWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TunezWeb.ErrorHTML, json: TunezWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Tunez.PubSub,
  live_view: [signing_salt: "2gskVQkA"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :tunez, Tunez.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  tunez: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.4",
  tunez: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
