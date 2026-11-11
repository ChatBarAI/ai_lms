class EntitlementEvent < ApplicationRecord
  belongs_to :course_entitlement
  belongs_to :actor, class_name: "User", optional: true
  validates :source, :action, :reason, :correlation_reference, presence: true

  def readonly?
    persisted?
  end
end
