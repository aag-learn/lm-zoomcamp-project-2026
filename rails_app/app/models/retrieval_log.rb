class RetrievalLog < ApplicationRecord
  belongs_to :message

  validates :retrieval_strategy, presence: true
end
