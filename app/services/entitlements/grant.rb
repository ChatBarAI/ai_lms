module Entitlements
  class Grant
    def self.call(user:, course:, source:, reference:, reason:, actor: nil, purchase: nil, expires_at: nil)
      raise ArgumentError, "Reason required" if reason.blank?
      raise CanCan::AccessDenied unless source == "stripe" ? purchase&.user_id == user.id && purchase.course_id == course.id : actor&.admin?
      # Course lock also serializes grandfathering with grant creation.
      course.with_lock do
        grant = CourseEntitlement.find_or_initialize_by(source: source, source_reference: reference)
        if grant.persisted?
          raise ArgumentError, "Grant identity mismatch" unless grant.user_id == user.id && grant.course_id == course.id && grant.purchase_id == purchase&.id
          return grant # Replays never restore revoked access.
        end
        grant.assign_attributes(user: user, course: course, purchase: purchase, granted_by: actor,
          starts_at: Time.current, expires_at: expires_at, reason: reason)
        grant.save!
        grant.entitlement_events.create!(actor: actor, source: source, action: "grant", reason: reason, correlation_reference: reference)
        grant
      end
    end
  end
end
