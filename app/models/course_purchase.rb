class CoursePurchase < ApplicationRecord
  belongs_to :user
  belongs_to :course

  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :user_id, uniqueness: { scope: :course_id, message: "has already purchased this course" }

  def amount
    amount_cents / 100.0
  end
end
