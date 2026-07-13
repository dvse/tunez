# Tunez

The starter app for the upcoming [Ash Framework](https://pragprog.com/titles/ldash/ash-framework/) book.

## Setup

The versions of Elixir and Erlang we're using are specified in the `.tool-versions` file. Tunez should work with any reasonably recent versions, but newer is better!

* If you're using `asdf` to manage installed versions of languages, run `asdf install` to install them. 
* If you're using `mise` to manage installed versions of languages, run `mise install` to install them. 

Once you have those installed:

* Run `mix setup` to install and setup Elixir dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Codex with the Tunez MCP server

With Tunez running on port 4000, run the following from the Tunez repository root to start a
one-off Codex session connected to its MCP endpoint:

```sh
set -euo pipefail

TUNEZ_EMAIL='blueprint-admin@example.com'
TUNEZ_PASSWORD='blueprint-password'

TUNEZ_MCP_TOKEN="$(
  jq -nc \
    --arg email "$TUNEZ_EMAIL" \
    --arg password "$TUNEZ_PASSWORD" \
    '{data: {type: "user", attributes: {email: $email, password: $password}}}' |
  curl -fsS \
    -H 'content-type: application/vnd.api+json' \
    --data-binary @- \
    http://127.0.0.1:4000/api/json/users/sign-in |
  jq -er '.meta.token'
)"
export TUNEZ_MCP_TOKEN

exec codex \
  -C "$(pwd)" \
  -a on-request \
  -c 'mcp_servers.tunez.url="http://127.0.0.1:4000/mcp"' \
  -c 'mcp_servers.tunez.bearer_token_env_var="TUNEZ_MCP_TOKEN"'
```

This requires `curl` and `jq`. Authentication failures stop the command before Codex starts. The
MCP configuration and bearer token apply only to that Codex process; neither is written to
persistent Codex configuration.
