defmodule Tunez.QueueActorPersister do
  @moduledoc false

  @behaviour AshQueue.ActorPersister

  @impl AshQueue.ActorPersister
  def store(%Tunez.Accounts.User{id: id, role: role}) do
    %{"id" => id, "role" => Atom.to_string(role)}
  end

  def store(_actor), do: {:error, "Tunez queue work requires a user actor"}

  @impl AshQueue.ActorPersister
  def lookup(%{"id" => id, "role" => role}) do
    case role do
      "admin" -> {:ok, %Tunez.Accounts.User{id: id, role: :admin}}
      "editor" -> {:ok, %Tunez.Accounts.User{id: id, role: :editor}}
      "user" -> {:ok, %Tunez.Accounts.User{id: id, role: :user}}
      _role -> {:error, "stored Tunez queue actor has an invalid role"}
    end
  end

  def lookup(_stored), do: {:error, "stored Tunez queue actor is invalid"}
end
