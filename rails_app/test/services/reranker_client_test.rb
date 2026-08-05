require "test_helper"

class RerankerClientTest < ActiveSupport::TestCase
  test "rerank returns scores in input order" do
    stub_request(:post, "http://embedder:8000/rerank")
      .with(body: { query: "copy a file", candidates: %w[src dest] }.to_json)
      .to_return(
        status: 200,
        body: { scores: [ 0.9, 0.2 ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = RerankerClient.rerank(query: "copy a file", candidates: %w[src dest])

    assert_equal [ 0.9, 0.2 ], result
  end

  test "rerank returns an empty array for an empty candidate list without making a request" do
    result = RerankerClient.rerank(query: "copy a file", candidates: [])

    assert_equal [], result
  end

  test "rerank retries a transient failure and returns the eventual success" do
    stub_request(:post, "http://embedder:8000/rerank")
      .to_return(status: 503, body: "service unavailable")
      .to_return(
        status: 200,
        body: { scores: [ 0.9 ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = RerankerClient.rerank(query: "copy a file", candidates: [ "src" ])

    assert_equal [ 0.9 ], result
    assert_requested :post, "http://embedder:8000/rerank", times: 2
  end

  test "rerank raises after exhausting retries against a persistently failing embedder" do
    stub_request(:post, "http://embedder:8000/rerank")
      .to_return(status: 503, body: "service unavailable")

    assert_raises(RerankerClient::RerankError) do
      RerankerClient.rerank(query: "copy a file", candidates: [ "src" ])
    end
  end
end
