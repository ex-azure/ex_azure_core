defmodule ExAzureCore.Credentials.AzureKeyCredentialTest do
  use ExUnit.Case, async: true

  alias ExAzureCore.Credentials.AzureKeyCredential
  alias ExAzureCore.Credentials.Errors.CredentialError

  describe "new/1" do
    test "creates credential with valid key" do
      assert {:ok, %AzureKeyCredential{key: "my-api-key"}} = AzureKeyCredential.new("my-api-key")
    end

    test "returns error for empty string" do
      assert {:error, %CredentialError{type: :invalid_key}} = AzureKeyCredential.new("")
    end

    test "returns error for nil" do
      assert {:error, %CredentialError{type: :invalid_key}} = AzureKeyCredential.new(nil)
    end

    test "returns error for non-string values" do
      assert {:error, %CredentialError{type: :invalid_key}} = AzureKeyCredential.new(123)
      assert {:error, %CredentialError{type: :invalid_key}} = AzureKeyCredential.new(:atom)
      assert {:error, %CredentialError{type: :invalid_key}} = AzureKeyCredential.new(~c"list")
    end
  end

  describe "new!/1" do
    test "returns credential with valid key" do
      assert %AzureKeyCredential{key: "my-api-key"} = AzureKeyCredential.new!("my-api-key")
    end

    test "raises on invalid key" do
      assert_raise CredentialError, fn ->
        AzureKeyCredential.new!("")
      end
    end
  end

  describe "update/2" do
    test "returns new credential with updated key" do
      {:ok, original} = AzureKeyCredential.new("old-key")

      assert {:ok, %AzureKeyCredential{key: "new-key"}} =
               AzureKeyCredential.update(original, "new-key")
    end

    test "original credential is unchanged" do
      {:ok, original} = AzureKeyCredential.new("old-key")
      {:ok, _updated} = AzureKeyCredential.update(original, "new-key")
      assert original.key == "old-key"
    end

    test "returns error for invalid new key" do
      {:ok, original} = AzureKeyCredential.new("old-key")

      assert {:error, %CredentialError{type: :invalid_key}} =
               AzureKeyCredential.update(original, "")
    end
  end
end
