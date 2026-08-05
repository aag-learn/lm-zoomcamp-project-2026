require "test_helper"

class MonitoringsControllerTest < ActionDispatch::IntegrationTest
  test "shows placeholders when there is no data yet" do
    get monitoring_path

    assert_response :success
    assert_match "0", response.body
  end

  test "shows real aggregate figures once there is data" do
    chat = Chat.create!
    message = chat.messages.create!(role: "user", content: "hi")
    RetrievalLog.create!(message: message, retrieval_strategy: "hybrid_rerank", response_time: 1.5, cost: 0.01)
    Feedback.create!(message: message, rating: 1)

    get monitoring_path

    assert_response :success
    assert_match "1.5", response.body
  end
end
