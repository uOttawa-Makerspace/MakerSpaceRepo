# frozen_string_literal: true

# Characterization helpers for the JobOrders subsystem (chunk 6).
#
# Why this exists: `JobStatus::DRAFT` (and every other JobStatus constant) is
# resolved ONCE at boot (`JobStatus.find_by(name: "Draft")` in the class body)
# while the TEST database ships empty. Without these reference rows the
# controller's status machinery operates on nils, which is NOT how the app
# behaves in any deployed environment (production tables hold rows created by
# db/migrate/*.rb). Each example that exercises the status machine asks this
# helper to create the exact migration-shipped rows and to point the boot-time
# constants at them (same pattern already used for BookingStatus in
# spec/controllers/subspace_bookings_controller_spec.rb).
#
# JobType / JobOrderMessage rows follow the shipped migrations too (they are
# referenced by name in the views/controller but never resolved through a
# constant, so no stubbing is needed for them).
module JobOrderSpecHelpers
  include ActiveSupport::Testing::TimeHelpers

  JOB_STATUS_NAMES = {
    draft: "Draft",
    staff_approval: "Waiting for Staff Approval",
    user_approval: "Waiting for User Approval",
    sent_reminder: "Sent a Quote Reminder",
    waiting_processed: "Waiting to be Processed",
    being_processed: "Currently being Processed",
    completed: "Completed (Waiting for Payment)",
    paid: "Paid (Waiting for Pick-Up)",
    picked_up: "Picked-Up",
    declined: "Declined"
  }.freeze

  # Constant name -> JOB_STATUS_NAMES key, mirroring db/migrate data + class.
  JOB_STATUS_CONSTANTS = {
    "JobStatus::DRAFT" => :draft,
    "JobStatus::STAFF_APPROVAL" => :staff_approval,
    "JobStatus::USER_APPROVAL" => :user_approval,
    "JobStatus::SENT_REMINDER" => :sent_reminder,
    "JobStatus::WAITING_PROCESSED" => :waiting_processed,
    "JobStatus::BEING_PROCESSED" => :being_processed,
    "JobStatus::COMPLETED" => :completed,
    "JobStatus::PAID" => :paid,
    "JobStatus::PICKED_UP" => :picked_up,
    "JobStatus::DECLINED" => :declined
  }.freeze

  def seed_job_statuses!
    rows = seed_rows_with_status_constants!
    stub_job_status_constants!(rows)
    rows
  end

  # Advanced the JobStatus boot-constants without creating rows (call when the
  # example already created the rows it needs).
  def stub_job_status_constants!(rows = nil)
    rows ||= seed_rows_with_status_constants!
    JOB_STATUS_CONSTANTS.each do |const_name, key|
      stub_const(const_name, rows.fetch(key))
    end
    rows
  end

  # Legacy migration data (print_order_messages → job_order_messages). The
  # controller dereferences this row on every JobOrders#show
  # (`JobOrderMessage.find_by(name: "processed").retrieve_message…`), so the
  # row must exist in any deployed DB. [QUOTED_BALANCE] / [PRINT_ID] are the
  # placeholders retrieve_message substitutes.
  def seed_job_order_message!
    JobOrderMessage.find_by(name: "processed") ||
      JobOrderMessage.create!(
        name: "processed",
        message:
          "<div>Your print has completed and is now available for pickup! " \
          "Your order ID is [PRINT_ID] and your quoted balance is [QUOTED_BALANCE].</div>"
      )
  end

  # JobType names shipped by db/migrate/20220206202756_create_job_types.rb.
  def seed_job_types!
    {
      "3D Print" => "Submit a file to be 3D Printed in our MakerSpace",
      "Laser Cut" => "Submit a file to be Laser Cutted in our MakerSpace",
      "Design Services" => "Create the design you want with the help of our employees"
    }.each do |name, description|
      next if JobType.find_by(name: name)

      JobType.create!(name: name, description: description)
    end
  end

  # A real order with an (owner-owned) status history entry.
  def make_job_order!(owner:, status_key: :draft, staff: nil)
    rows = seed_job_statuses!
    order = create(:job_order, user: owner)
    order.job_order_statuses.create!(
      job_status: rows.fetch(status_key),
      user: staff || owner
    )
    order
  end

  # Real login POST (the AuthzTestHelper session shim recurses infinitely in
  # type: :request specs; repo precedent: sub_space_booking_request_spec.rb
  # drives login_authentication_path for the same reason).
  def session_login!(user, password: TEST_USER_PASSWORD)
    post login_authentication_path,
         params: { username_email: user.username, password: password }
    expect(response).to redirect_to(root_path)
    user
  end

  # The token the mailer generates (JobOrderMailer#send_job_quote uses
  # `Rails.application.message_verifier(:job_order_id).generate(order_id)`) and
  # the controller verifies. Producing it here uses the same verifier so the
  # characterization hits the real signed-token seam.
  def magic_link_token_for(job_order)
    Rails.application.message_verifier(:job_order_id).generate(job_order.id)
  end

  # Same plaintext the seeded user fixture bundle answers (BCrypt factory
  # hash in spec/factories/users.rb).
  TEST_USER_PASSWORD = "asa32A353#"

  private

  def seed_rows_with_status_constants!
    JOB_STATUS_NAMES.each_with_object({}) do |(key, name), memo|
      memo[key] =
        JobStatus.find_by(name: name) ||
        JobStatus.create!(name: name, description: "#{name} (test reference row)")
    end
  end

  public
end

RSpec.configure do |config|
  config.include JobOrderSpecHelpers, type: :request
  config.include JobOrderSpecHelpers, type: :system
end
