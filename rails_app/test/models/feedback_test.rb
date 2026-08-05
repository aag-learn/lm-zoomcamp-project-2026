require "test_helper"

class FeedbackTest < ActiveSupport::TestCase
  setup do
    chat = Chat.create!
    @message = chat.messages.create!(role: "assistant", content: "hello")
  end

  test "valid with a rating of 1 or -1" do
    assert Feedback.new(message: @message, rating: 1).valid?
    assert Feedback.new(message: @message, rating: -1).valid?
  end

  test "invalid with any other rating" do
    feedback = Feedback.new(message: @message, rating: 0)

    assert_not feedback.valid?
    assert_includes feedback.errors[:rating], "is not included in the list"
  end

  test "only one feedback per message at the database level" do
    Feedback.create!(message: @message, rating: 1)

    assert_raises(ActiveRecord::RecordNotUnique) do
      Feedback.create!(message: @message, rating: -1)
    end
  end
end
