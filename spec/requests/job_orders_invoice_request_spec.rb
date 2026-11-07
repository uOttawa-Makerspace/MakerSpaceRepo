# frozen_string_literal: true

require "rails_helper"

# The printable invoice lists the quote's lines and a total. Both come from the same quote rows, and a paid
# order's quote cannot be changed afterwards, so the listed lines always add up to the total shown.
RSpec.describe "Job order invoice", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
  end

  def listed_amounts(body)
    body.scan(/^\s*CAD \$([\d,]+\.\d\d)/).flatten.map { |amount| BigDecimal(amount.delete(",")) }
  end

  def shown_total(body)
    BigDecimal(body[/Total: CAD \$([\d,]+\.\d\d)/, 1].delete(","))
  end

  it "lists lines that add up to the total shown" do
    order = add_quoted_tasks!(make_job_order!(owner: owner, status_key: :paid))
    session_login!(owner)

    get job_order_invoice_path(order)

    expect(listed_amounts(response.body)).to contain_exactly(20, 12, 7.25, 15.5, 2.5, 1.25)
    expect(listed_amounts(response.body).sum).to eq(shown_total(response.body))
    expect(shown_total(response.body)).to eq(BigDecimal("58.5"))
  end

  it "still adds up after a staff re-quote of the paid order is refused" do
    order = add_quoted_tasks!(make_job_order!(owner: owner, status_key: :paid))
    task = order.job_tasks.find_by!(title: "Print B")
    session_login!(staff)

    patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task.id}" => "99" }
    expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.quote_refused_paid"))

    get job_order_invoice_path(order)
    expect(listed_amounts(response.body).sum).to eq(shown_total(response.body))
    expect(shown_total(response.body)).to eq(BigDecimal("58.5"))
  end
end
