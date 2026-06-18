class Rating < ApplicationRecord
  belongs_to :user
  belongs_to :lesson

  validates :stars,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 },
            allow_nil: true
  validates :user_id, uniqueness: { scope: :lesson_id }
end
