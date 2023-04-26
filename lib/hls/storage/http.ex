defmodule HLS.Storage.HTTP do
  defstruct [:url, :client, follow_redirects?: false]

  def new(url, follow_redirects? \\ false) do
    uri = URI.parse(url)
    base_url = "#{uri.scheme}://#{uri.authority}#{Path.dirname(uri.path)}"

    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Retry,
       delay: 100,
       max_retries: 10,
       max_delay: 1_000,
       should_retry: fn
         {:ok, %{status: status}} when status >= 400 and status <= 500 -> true
         {:error, _} -> true
         {:ok, _} -> false
       end}
    ]

    middleware =
      if follow_redirects? do
        middleware ++ [Tesla.Middleware.FollowRedirects]
      else
        middleware
      end

    %__MODULE__{client: Tesla.client(middleware), url: url, follow_redirects?: follow_redirects?}
  end
end

defimpl HLS.Storage.Driver, for: HLS.Storage.HTTP do
  @impl true
  def get(%HLS.Storage.HTTP{client: client, url: url}) do
    client
    |> Tesla.get(url)
    |> handle_response()
  end

  @impl true
  def get(%HLS.Storage.HTTP{client: client}, uri) do
    client
    |> Tesla.get(uri.path, query: decode_query(uri.query))
    |> handle_response()
  end

  @impl true
  def ready?(%HLS.Storage.HTTP{url: url} = config) do
    middleware = if config.follow_redirects?, do: [Tesla.Middleware.FollowRedirects], else: []
    client = Tesla.client(middleware)

    case Tesla.head(client, url) do
      {:ok, %{status: 200}} -> true
      _other -> false
    end
  end

  defp decode_query(nil), do: []

  defp decode_query(raw) when is_binary(raw) do
    raw
    |> URI.decode_query()
    |> Enum.into([])
  end

  defp handle_response({:ok, %Tesla.Env{body: body, status: 200}}), do: {:ok, body}
  defp handle_response({:ok, %Tesla.Env{status: status}}), do: {:error, {:status, status}}
  defp handle_response(err = {:error, _reason}), do: err
end
