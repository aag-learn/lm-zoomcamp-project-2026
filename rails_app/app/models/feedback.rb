class Feedback < ApplicationRecord
  belongs_to :message

  validates :rating, inclusion: { in: [ -1, 1 ] }
end
