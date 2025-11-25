defmodule ExAzureCore.Errors do
  @moduledoc """
  Defines the error types for the Azure SDK.
  """
  @moduledoc section: :errors
  use Splode,
    error_classes: [
      invalid: ExAzureCore.Errors.Invalid,
      internal: ExAzureCore.Errors.Internal,
      external: ExAzureCore.Errors.External,
      authentication: ExAzureCore.Errors.Authentication
    ],
    unknown_error: ExAzureCore.Errors.Unknown
end

defmodule ExAzureCore.Errors.Authentication do
  @moduledoc """
  Defines the error type related to authentication failures.
  """
  @moduledoc section: :errors
  use Splode.ErrorClass, class: :authentication

  @type t() :: Splode.Error.t()
end

defmodule ExAzureCore.Errors.Internal do
  @moduledoc """
  Define an error class for internal sdk errors.
  """
  @moduledoc section: :errors
  use Splode.ErrorClass, class: :internal

  @type t() :: Splode.Error.t()
end

defmodule ExAzureCore.Errors.External do
  @moduledoc """
  Define an error class for external service errors.
  """
  @moduledoc section: :errors
  use Splode.ErrorClass, class: :external

  @type t() :: Splode.Error.t()
end

defmodule ExAzureCore.Errors.Invalid do
  @moduledoc """
  Defines the error type for invalid requests to Azure Services.
  """
  @moduledoc section: :errors
  use Splode.ErrorClass, class: :invalid

  @type t() :: Splode.Error.t()
end

defmodule ExAzureCore.Errors.Unknown do
  @moduledoc """
  Defines the error type for an unknown error.
  """
  @moduledoc section: :errors
  use Splode.ErrorClass, class: :unknown

  @type t() :: Splode.Error.t()
end
