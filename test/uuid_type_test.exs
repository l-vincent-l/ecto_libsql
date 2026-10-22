defmodule EctoLibSql.UuidTypeTest do
  @moduledoc """
  Tests for the storage of `:uuid` fields (`Ecto.UUID`, also the type of Ash
  UUID attributes), chosen with the `:uuid_type` application environment, as
  in `ecto_sqlite3`:

      config :ecto_libsql, uuid_type: :string

  `:binary`, the default, stores them as 16-byte BLOBs; `:string` stores them
  as TEXT. `:binary_id` fields are stored as TEXT either way.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  defmodule TestRepo do
    use Ecto.Repo,
      otp_app: :ecto_libsql,
      adapter: Ecto.Adapters.LibSql
  end

  defmodule Item do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "items" do
      field(:ref, Ecto.UUID)
    end
  end

  @test_db "z_ecto_libsql_test-uuid_type.db"

  setup_all do
    {:ok, _} = TestRepo.start_link(database: @test_db)

    # The column types the migrations create for :binary_id and :uuid.
    Ecto.Adapters.SQL.query!(TestRepo, """
    CREATE TABLE IF NOT EXISTS items (id TEXT PRIMARY KEY, ref TEXT)
    """)

    on_exit(fn ->
      EctoLibSql.TestHelpers.cleanup_db_files(@test_db)
    end)

    :ok
  end

  setup do
    Ecto.Adapters.SQL.query!(TestRepo, "DELETE FROM items")

    previous = Application.fetch_env(:ecto_libsql, :uuid_type)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:ecto_libsql, :uuid_type, value)
        :error -> Application.delete_env(:ecto_libsql, :uuid_type)
      end
    end)

    :ok
  end

  # How SQLite stores `column` of the only item: its type and its value.
  defp stored(column) do
    %{rows: [row]} =
      Ecto.Adapters.SQL.query!(TestRepo, "SELECT typeof(#{column}), #{column} FROM items")

    List.to_tuple(row)
  end

  describe "uuid_type: :binary (default)" do
    setup do
      Application.delete_env(:ecto_libsql, :uuid_type)
    end

    test "stores :uuid fields as 16-byte BLOBs" do
      ref = Ecto.UUID.generate()
      TestRepo.insert!(%Item{ref: ref})

      assert stored("ref") == {"blob", Ecto.UUID.dump!(ref)}
    end

    test "loads them back as UUID strings, and finds them by value" do
      ref = Ecto.UUID.generate()
      %{id: id} = TestRepo.insert!(%Item{ref: ref})

      assert %Item{id: ^id, ref: ^ref} = TestRepo.get!(Item, id)
      assert [%Item{id: ^id}] = TestRepo.all(from(i in Item, where: i.ref == ^ref))
      assert [%Item{id: ^id}] = TestRepo.all(from(i in Item, where: i.ref in ^[ref]))
    end
  end

  describe "uuid_type: :string" do
    setup do
      Application.put_env(:ecto_libsql, :uuid_type, :string)
    end

    test "stores :uuid fields as TEXT" do
      ref = Ecto.UUID.generate()
      TestRepo.insert!(%Item{ref: ref})

      assert stored("ref") == {"text", ref}
    end

    test "loads them back as UUID strings, and finds them by value" do
      ref = Ecto.UUID.generate()
      %{id: id} = TestRepo.insert!(%Item{ref: ref})

      assert %Item{id: ^id, ref: ^ref} = TestRepo.get!(Item, id)
      assert [%Item{id: ^id}] = TestRepo.all(from(i in Item, where: i.ref == ^ref))
      assert [%Item{id: ^id}] = TestRepo.all(from(i in Item, where: i.ref in ^[ref]))
    end

    test "updates them as TEXT" do
      item = TestRepo.insert!(%Item{ref: Ecto.UUID.generate()})
      ref = Ecto.UUID.generate()
      item |> Ecto.Changeset.change(ref: ref) |> TestRepo.update!()

      assert stored("ref") == {"text", ref}
    end
  end

  test "an invalid uuid_type raises" do
    Application.put_env(:ecto_libsql, :uuid_type, :text)

    assert_raise ArgumentError, ~r/invalid :uuid_type/, fn ->
      TestRepo.insert!(%Item{ref: Ecto.UUID.generate()})
    end
  end

  describe ":binary_id" do
    for uuid_type <- [:binary, :string] do
      test "is stored as TEXT with uuid_type: #{inspect(uuid_type)}" do
        Application.put_env(:ecto_libsql, :uuid_type, unquote(uuid_type))
        item = TestRepo.insert!(%Item{ref: Ecto.UUID.generate()})

        assert stored("id") == {"text", item.id}
        assert %Item{} = TestRepo.get!(Item, item.id)
      end
    end
  end
end
