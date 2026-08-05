class MonitoringsController < ApplicationController
  def show
    @total_queries = RetrievalLog.count
    @avg_response_time = RetrievalLog.average(:response_time)
    @total_cost = RetrievalLog.sum(:cost)
    @feedback_ratio = feedback_ratio
    @grafana_port = ENV.fetch("GRAFANA_PORT", "3001")
  end

  private

  def feedback_ratio
    total = Feedback.count
    return nil if total.zero?

    Feedback.where(rating: 1).count.to_f / total
  end
end
