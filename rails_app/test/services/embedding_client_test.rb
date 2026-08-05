require "test_helper"

class EmbeddingClientTest < ActiveSupport::TestCase
  test "embed returns embeddings in input order" do
    stub_request(:post, "http://embedder:8000/embed")
      .with(body: { texts: %w[hello world] }.to_json)
      .to_return(
        status: 200,
        body: { embeddings: [ [ 0.1, 0.2 ], [ 0.3, 0.4 ] ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = EmbeddingClient.embed(%w[hello world])

    assert_equal [ [ 0.1, 0.2 ], [ 0.3, 0.4 ] ], result
  end

  test "embed returns an empty array for an empty batch without making a request" do
    result = EmbeddingClient.embed([])

    assert_equal [], result
  end

  test "embed retries a transient failure and returns the eventual success" do
    stub_request(:post, "http://embedder:8000/embed")
      .to_return(status: 503, body: "service unavailable")
      .to_return(
        status: 200,
        body: { embeddings: [ [ 0.1, 0.2 ] ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = EmbeddingClient.embed([ "hello" ])

    assert_equal [ [ 0.1, 0.2 ] ], result
    assert_requested :post, "http://embedder:8000/embed", times: 2
  end

  test "embed raises after exhausting retries against a persistently failing embedder" do
    stub_request(:post, "http://embedder:8000/embed")
      .to_return(status: 503, body: "service unavailable")

    assert_raises(EmbeddingClient::EmbedError) do
      EmbeddingClient.embed([ "hello" ])
    end
  end
end
