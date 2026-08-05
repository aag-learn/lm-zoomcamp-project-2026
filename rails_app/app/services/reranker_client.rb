class RerankerClient
  class RerankError < StandardError; end

  def self.rerank(query:, candidates:)
    new.rerank(query: query, candidates: candidates)
  end

  def initialize(base_url: ENV.fetch("EMBEDDER_URL", "http://embedder:8000"))
    @connection = Faraday.new(url: base_url) do |f|
      f.request :retry, max: 3, interval: 0.5, backoff_factor: 2,
                         methods: [ :post ],
                         retry_statuses: [ 429, 500, 502, 503, 504 ]
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def rerank(query:, candidates:)
    return [] if candidates.empty?

    response = connection.post("/rerank", query: query, candidates: candidates)
    raise RerankError, "embedder returned #{response.status}: #{response.body}" unless response.success?

    response.body["scores"]
  rescue Faraday::Error => e
    raise RerankError, "embedder request failed: #{e.message}"
  end

  private

  attr_reader :connection
end
