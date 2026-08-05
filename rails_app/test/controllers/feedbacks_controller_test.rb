require "test_helper"

class FeedbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    chat = Chat.create!
    @message = chat.messages.create!(role: "assistant", content: "hello")
  end

  test "submitting a rating creates a Feedback for that message" do
    assert_difference("Feedback.count", 1) do
      post message_feedback_path(@message), params: { feedback: { rating: 1 } }
    end

    assert_equal 1, @message.reload.feedback.rating
  end

  test "submitting a rating twice updates the same Feedback instead of creating a second one" do
    post message_feedback_path(@message), params: { feedback: { rating: 1 } }

    assert_no_difference("Feedback.count") do
      post message_feedback_path(@message), params: { feedback: { rating: -1 } }
    end

    assert_equal(-1, @message.reload.feedback.rating)
  end

  test "an invalid rating does not create a Feedback" do
    assert_no_difference("Feedback.count") do
      post message_feedback_path(@message), params: { feedback: { rating: 0 } }
    end
  end
end
