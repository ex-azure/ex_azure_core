defmodule ExAzureCore.Credentials.AzureSasCredentialTest do
  use ExUnit.Case, async: true

  alias ExAzureCore.Credentials.AzureSasCredential
  alias ExAzureCore.Credentials.Errors.CredentialError

  describe "new/1" do
    test "creates credential with valid signature" do
      signature = "sv=2021-06-08&ss=b&srt=sco&sp=rwdlacupitfx"
      assert {:ok, %AzureSasCredential{signature: ^signature}} = AzureSasCredential.new(signature)
    end

    test "normalizes signature by stripping leading ?" do
      assert {:ok, %AzureSasCredential{signature: "sv=2021-06-08&ss=b"}} =
               AzureSasCredential.new("?sv=2021-06-08&ss=b")
    end

    test "trims whitespace from signature" do
      assert {:ok, %AzureSasCredential{signature: "sv=2021-06-08"}} =
               AzureSasCredential.new("  sv=2021-06-08  ")
    end

    test "returns error for empty string" do
      assert {:error, %CredentialError{type: :invalid_signature}} = AzureSasCredential.new("")
    end

    test "returns error for only ? character" do
      assert {:error, %CredentialError{type: :invalid_signature}} = AzureSasCredential.new("?")
    end

    test "returns error for only whitespace" do
      assert {:error, %CredentialError{type: :invalid_signature}} = AzureSasCredential.new("   ")
    end

    test "returns error for nil" do
      assert {:error, %CredentialError{type: :invalid_signature}} = AzureSasCredential.new(nil)
    end

    test "returns error for non-string values" do
      assert {:error, %CredentialError{type: :invalid_signature}} = AzureSasCredential.new(123)
      assert {:error, %CredentialError{type: :invalid_signature}} = AzureSasCredential.new(:atom)
    end
  end

  describe "new!/1" do
    test "returns credential with valid signature" do
      signature = "sv=2021-06-08&ss=b"
      assert %AzureSasCredential{signature: ^signature} = AzureSasCredential.new!(signature)
    end

    test "raises on invalid signature" do
      assert_raise CredentialError, fn ->
        AzureSasCredential.new!("")
      end
    end
  end

  describe "update/2" do
    test "returns new credential with updated signature" do
      {:ok, original} = AzureSasCredential.new("old-signature")

      assert {:ok, %AzureSasCredential{signature: "new-signature"}} =
               AzureSasCredential.update(original, "new-signature")
    end

    test "original credential is unchanged" do
      {:ok, original} = AzureSasCredential.new("old-signature")
      {:ok, _updated} = AzureSasCredential.update(original, "new-signature")
      assert original.signature == "old-signature"
    end

    test "normalizes new signature" do
      {:ok, original} = AzureSasCredential.new("old-signature")

      assert {:ok, %AzureSasCredential{signature: "new-signature"}} =
               AzureSasCredential.update(original, "?new-signature")
    end

    test "returns error for invalid new signature" do
      {:ok, original} = AzureSasCredential.new("old-signature")

      assert {:error, %CredentialError{type: :invalid_signature}} =
               AzureSasCredential.update(original, "")
    end
  end
end
