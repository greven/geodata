defmodule GeoData.ExceptionTest do
  use ExUnit.Case, async: true

  alias GeoData.DownloadError
  alias GeoData.IngestError
  alias GeoData.NoNameError
  alias GeoData.NotFoundError
  alias GeoData.ValidationError

  @exceptions [ValidationError, NoNameError, NotFoundError, DownloadError, IngestError]

  describe "reason_atoms/0" do
    test "every exception declares a non-empty closed set" do
      for module <- @exceptions do
        reasons = module.reason_atoms()

        assert is_list(reasons)
        assert reasons != []
      end
    end
  end

  describe "message/1" do
    test "renders a message for every declared reason" do
      for module <- @exceptions, reason <- module.reason_atoms() do
        message = module |> build(reason) |> Exception.message()

        assert is_binary(message)
        assert message != ""
      end
    end

    test "validation :missing names the field" do
      error = struct!(ValidationError, field: :kind, reason: :missing)

      assert Exception.message(error) == "missing required field :kind"
    end

    test "validation :invalid_kind lists the allowed values" do
      error =
        struct!(ValidationError,
          field: :kind,
          value: :county,
          reason: :invalid_kind,
          allowed_values: [:city, :country]
        )

      assert Exception.message(error) =~ "invalid value :county"
      assert Exception.message(error) =~ "[:city, :country]"
    end

    test "validation :invalid_type names the expected type" do
      error =
        struct!(ValidationError,
          field: :id,
          value: 1,
          reason: :invalid_type,
          expected: :binary
        )

      assert Exception.message(error) =~ "expected :binary"
    end

    test "no name reports the place id and locale" do
      error = struct!(NoNameError, place: %{id: "GN:1"}, locale: :en)

      assert Exception.message(error) =~ "GN:1"
      assert Exception.message(error) =~ ":en"
    end

    test "not found reports the id" do
      error = struct!(NotFoundError, id: "ISO:XX")

      assert Exception.message(error) =~ "ISO:XX"
    end
  end

  describe "exception/1" do
    test "rejects unknown bindings" do
      assert_raise KeyError, fn -> ValidationError.exception(unknown: 1) end
    end
  end

  defp build(ValidationError, reason) do
    struct!(ValidationError,
      field: :kind,
      value: :bogus,
      reason: reason,
      expected: :binary,
      allowed_values: [:city]
    )
  end

  defp build(NoNameError, reason) do
    struct!(NoNameError, place: %{id: "GN:1"}, locale: :en, reason: reason)
  end

  defp build(NotFoundError, reason) do
    struct!(NotFoundError, id: "GN:1", reason: reason)
  end

  defp build(DownloadError, reason) do
    struct!(DownloadError, url: "https://example.com/a", path: "/tmp/a", reason: reason)
  end

  defp build(IngestError, reason) do
    struct!(IngestError, source: :iso_codes, file: "/tmp/a", reason: reason)
  end
end
