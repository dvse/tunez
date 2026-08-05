defmodule Tunez.UI.Blueprint do
  require Tunez.UI.PageLifeDomain

  use AshBlueprint.Substrate,
    page_life: {Tunez.UI.PageLifeDomain, :begin_page_life}
end
