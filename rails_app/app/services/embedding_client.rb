class EmbeddingClient
  class EmbedError < StandardError; end

  def self.embed(texts)
    new.embed(texts)
  end

  def initialize(base_url: ENV.fetch("EMBEDDER_URL", "http://embedder:8000"))
    @connection = Faraday.new(url: base_url) do |f|
      # faraday-retry's default `methods:` list only covers idempotent verbs
      # (GET/HEAD/PUT/DELETE/OPTIONS) — POST must be added explicitly or
      # nothing below ever retries, regardless of `exceptions`/`retry_statuses`.
      f.request :retry, max: 3, interval: 0.5, backoff_factor: 2,
                         methods: [ :post ],
                         retry_statuses: [ 429, 500, 502, 503, 504 ]
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def embed(texts)
    return [] if texts.empty?

    response = connection.post("/embed", texts: texts)
    raise EmbedError, "embedder returned #{response.status}: #{response.body}" unless response.success?

    response.body["embeddings"]
  rescue Faraday::Error => e
    raise EmbedError, "embedder request failed: #{e.message}"
  end

  private

  attr_reader :connection
end
