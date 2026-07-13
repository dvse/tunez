defmodule Tunez.MCP do
  use Ash.Domain, otp_app: :tunez, extensions: [AshLua.Domain, AshAi]

  lua do
    name "mcp"
  end

  tools do
    tool :tunez_lua_docs, Tunez.MCP.Actions, :docs do
      description """
      Discover the Tunez Lua API. With no input, returns the complete scoped API reference;
      with `search`, returns matching operation and type names; with `name`, returns the
      reference for one operation or type. This tool does not mutate state and returns Markdown.
      """
    end

    tool :tunez_lua_eval, Tunez.MCP.Actions, :eval do
      description """
      Evaluate one sandboxed Lua script against Tunez through ordinary policy-checked Ash
      actions. Requires `script`; may read or mutate state only through the documented scoped
      actions, using the MCP request's actor and tenant. Returns result, structured error, and
      captured print output.
      """
    end
  end

  resources do
    resource Tunez.MCP.Actions do
      define :lua_docs, action: :docs
      define :eval_lua, action: :eval, args: [:script]
    end
  end
end
