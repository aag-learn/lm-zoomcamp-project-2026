class FeedbacksController < ApplicationController
  before_action :set_message

  def create
    @feedback = @message.feedback || @message.build_feedback
    @feedback.rating = params.dig(:feedback, :rating)

    if @feedback.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @message.chat }
      end
    else
      redirect_to @message.chat, alert: @feedback.errors.full_messages.to_sentence
    end
  end

  private

  def set_message
    @message = Message.find(params[:message_id])
  end
end
