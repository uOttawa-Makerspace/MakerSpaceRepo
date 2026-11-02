# frozen_string_literal: true

# Characterization helpers for the JobOrders subsystem (chunk 6).
#
# Why this exists: JobStatus.draft (and every other JobStatus lookup) raises
# JobStatus::Missing while the TEST database ships empty. Each example that
# exercises the status machine asks this helper to create the exact
# migration-shipped rows (production tables hold rows created by
# db/migrate/*.rb) and to reset the per-process lookup memo.
#
# JobType / JobOrderMessage rows follow the shipped migrations too (they are
# referenced by name in the views/controller but never resolved through a
# constant, so no stubbing is needed for them).
module JobOrderSpecHelpers
  include ActiveSupport::Testing::TimeHelpers

  JOB_STATUS_NAMES = JobStatus::STATUS_NAMES

  # Creates the status rows the migrations ship (the test database starts empty) and forgets the memoized
  # JobStatus lookups, so JobStatus.draft etc. resolve to these rows.
  def seed_job_statuses!
    rows = seed_rows_with_status_lookups!
    JobStatus.reset_lookup_cache!
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

  # Quote with money in every place the customer/staff see it: two quoted
  # tasks (base fee + parts fee + an option price), plus two line items.
  #   Print A: 20.00 base + 4 x 3.00 parts + 7.25 option = 39.25
  #   Print B: 15.50 base
  #   line items: 2.50 + 1.25
  # Grand total 58.50. Returns the order.
  def add_quoted_tasks!(order)
    polish = JobOption.create!(name: "Polish", fee: 1)
    print_a = order.job_tasks.create!(title: "Print A")
    print_a.build_job_task_quote(price: 20, service_price: 3, service_quantity: 4).save!
    print_a.job_task_options.create!(job_option: polish)
    print_a.job_task_quote.job_task_quote_options.create!(job_option: polish, price: 7.25)
    order.job_tasks.create!(title: "Print B").build_job_task_quote(price: 15.5, service_price: 0, service_quantity: 0).save!
    order.job_quote_line_items.create!(description: "Rush", price: 2.5)
    order.job_quote_line_items.create!(description: "Setup", price: 1.25)
    order.reload
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

  # The emailed approval / pay tokens (JobOrder#approval_token / #pay_token),
  # produced the same way the mailer and views do.
  def magic_link_token_for(job_order)
    job_order.approval_token
  end

  def magic_pay_token_for(job_order)
    job_order.pay_token
  end

  # Same plaintext the seeded user fixture bundle answers (BCrypt factory
  # hash in spec/factories/users.rb).
  TEST_USER_PASSWORD = "asa32A353#"

  private

  def seed_rows_with_status_lookups!
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
