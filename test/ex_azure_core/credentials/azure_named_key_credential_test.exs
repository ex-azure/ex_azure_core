defmodule ExAzureCore.Credentials.AzureNamedKeyCredentialTest do
  use ExUnit.Case, async: true

  alias ExAzureCore.Credentials.AzureNamedKeyCredential
  alias ExAzureCore.Credentials.Errors.CredentialError

  describe "new/2" do
    test "creates credential with valid name and key" do
      assert {:ok, %AzureNamedKeyCredential{name: "myaccount", key: "mykey=="}} =
               AzureNamedKeyCredential.new("myaccount", "mykey==")
    end

    test "returns error for empty name" do
      assert {:error, %CredentialError{type: :invalid_named_key}} =
               AzureNamedKeyCredential.new("", "mykey")
    end

    test "returns error for empty key" do
      assert {:error, %CredentialError{type: :invalid_named_key}} =
               AzureNamedKeyCredential.new("myaccount", "")
    end

    test "returns error for both empty" do
      assert {:error, %CredentialError{type: :invalid_named_key}} =
               AzureNamedKeyCredential.new("", "")
    end

    test "returns error for nil name" do
      assert {:error, %CredentialError{type: :invalid_named_key}} =
               AzureNamedKeyCredential.new(nil, "mykey")
    end

    test "returns error for nil key" do
      assert {:error, %CredentialError{type: :invalid_named_key}} =
               AzureNamedKeyCredential.new("myaccount", nil)
    end

    test "returns error for non-string values" do
      assert {:error, %CredentialError{type: :invalid_named_key}} =
               AzureNamedKeyCredential.new(123, "mykey")

      assert {:error, %CredentialError{type: :invalid_named_key}} =
               AzureNamedKeyCredential.new("myaccount", :atom)
    end
  end

  describe "new!/2" do
    test "returns credential with valid name and key" do
      assert %AzureNamedKeyCredential{name: "myaccount", key: "mykey=="} =
               AzureNamedKeyCredential.new!("myaccount", "mykey==")
    end

    test "raises on invalid input" do
      assert_raise CredentialError, fn ->
        AzureNamedKeyCredential.new!("", "mykey")
      end
    end
  end

  describe "update/3" do
    test "returns new credential with updated values" do
      {:ok, original} = AzureNamedKeyCredential.new("oldaccount", "oldkey")

      assert {:ok, %AzureNamedKeyCredential{name: "newaccount", key: "newkey"}} =
               AzureNamedKeyCredential.update(original, "newaccount", "newkey")
    end

    test "original credential is unchanged" do
      {:ok, original} = AzureNamedKeyCredential.new("oldaccount", "oldkey")
      {:ok, _updated} = AzureNamedKeyCredential.update(original, "newaccount", "newkey")
      assert original.name == "oldaccount"
      assert original.key == "oldkey"
    end

    test "returns error for invalid new values" do
      {:ok, original} = AzureNamedKeyCredential.new("oldaccount", "oldkey")

      assert {:error, %CredentialError{type: :invalid_named_key}} =
               AzureNamedKeyCredential.update(original, "", "newkey")
    end
  end

  describe "named_key/1" do
    test "returns tuple of name and key" do
      {:ok, credential} = AzureNamedKeyCredential.new("myaccount", "mykey==")
      assert {"myaccount", "mykey=="} = AzureNamedKeyCredential.named_key(credential)
    end
  end
end
