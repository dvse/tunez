defmodule Tunez.UI.PageLifeDomain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Tunez.UI.PageLife do
      define :begin_page_life, action: :begin, args: [:session_id]
    end
  end
end
