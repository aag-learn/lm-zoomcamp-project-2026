class EvaluationsController < ApplicationController
  def show
    @ground_truth = Eval::GroundTruth.load
    @results = Eval::EvalResults.load
  end
end
