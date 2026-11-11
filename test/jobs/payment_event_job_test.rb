require "test_helper"

class PaymentEventJobTest < ActiveJob::TestCase
  test "already processed events are no ops" do
    event = PaymentEvent.create!(provider_event_id: "evt_done", account_id: "acct_test", livemode: false,
      event_type: "checkout.session.completed", object_id: "cs_done", state: "processed", processed_at: Time.current, attempts: 1)
    assert_no_difference [ "CourseEntitlement.count", "Enrollment.count" ] do
      PaymentEventJob.perform_now(event.id)
    end
    assert_equal 1, event.reload.attempts
  end
end
