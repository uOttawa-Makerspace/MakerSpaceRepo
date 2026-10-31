# frozen_string_literal: true

require "rails_helper"

# JobOrderMailer by DELIVERED outcome: recipient, bcc / reply-to, subject,
# priority headers and the body text that matters (quote token, reminder
# paragraph, sanitized completion message). Request specs pin the controller
# triggers; this pins the mails themselves, including the EXPEDITED variants.

RSpec.describe JobOrderMailer, type: :mailer do
  include JobOrderSpecHelpers

  let(:owner) { create(:user, :regular_user, name: "Pat Customer") }
  let(:staff) { create(:user, :staff) }
  let(:order) { make_job_order!(owner: owner, status_key: :user_approval) }

  before do
    seed_job_statuses!
    seed_job_order_message!
    ActionMailer::Base.deliveries.clear
    order.job_tasks.create!(title: "Task #1")
  end

  def delivered
    ActionMailer::Base.deliveries
  end

  def expedite!
    option = JobOption.create!(name: "Expedited Processing", fee: 5)
    order.job_tasks.first.job_task_options.create!(job_option: option)
  end

  describe ".send_job_submitted" do
    it "notifies the makerspace mailbox" do
      described_class.send_job_submitted(order.id).deliver_now
      expect(delivered.last.to).to eq(["makerspace@uottawa.ca"])
      expect(delivered.last.subject).to eq("A new Job Order has been submitted")
      expect(delivered.last.header["Importance"]).to be_nil
    end

    it "marks an EXPEDITED order with a subject prefix and high-priority headers" do
      expedite!
      described_class.send_job_submitted(order.id).deliver_now
      mail = delivered.last
      expect(mail.subject).to eq("EXPEDITED: A new Job Order has been submitted")
      expect(mail.header["Importance"].to_s).to eq("high")
      expect(mail.header["X-Priority"].to_s).to eq("1")
    end

    it "sends nothing for an unknown order" do
      described_class.send_job_submitted(99_999_999).deliver_now
      expect(delivered).to be_empty
    end
  end

  # JOB-01: the staff notification for an order sent back for a new quote
  describe ".send_job_requote_needed" do
    it "tells the makerspace mailbox which order needs a new quote and why" do
      described_class.send_job_requote_needed(order.id, "owner_change").deliver_now
      mail = delivered.last
      expect(mail.to).to eq(["makerspace@uottawa.ca"])
      expect(mail.subject).to eq("Job Order ##{order.id} needs a new quote")
      expect(mail.header["Importance"]).to be_nil
      text = Nokogiri::HTML(mail.body.decoded).text.squish
      expect(text).to include(I18n.t("job_orders.status_reasons.owner_change", locale: :en))
      expect(text).to include("previous payment link no longer works")
    end

    it "marks an EXPEDITED order with a subject prefix and high-priority headers" do
      expedite!
      described_class.send_job_requote_needed(order.id, "owner_change").deliver_now
      mail = delivered.last
      expect(mail.subject).to eq("EXPEDITED: Job Order ##{order.id} needs a new quote")
      expect(mail.header["Importance"].to_s).to eq("high")
    end

    it "sends nothing for an unknown order" do
      described_class.send_job_requote_needed(99_999_999, "owner_change").deliver_now
      expect(delivered).to be_empty
    end
  end

  describe ".send_job_quote" do
    it "mails the customer with reply-to, bcc and an approval link that resolves to the order id" do
      described_class.send_job_quote(order.id).deliver_now

      mail = delivered.last
      expect(mail.to).to eq([owner.email])
      expect(mail.reply_to).to eq(["makerspace@uottawa.ca"])
      expect(mail.bcc).to eq(["uottawa.makerepo@gmail.com"])
      expect(mail.subject)
        .to eq("Votre commande ##{order.id} a été approuvée // Your job order ##{order.id} has been approved")
      token = CGI.unescape(mail.body.decoded[/user_magic_approval\?token=([^"&\s]+)/, 1].to_s)
      expect(JobOrder.from_approval_token(token)).to eq(order)
      expect(JobOrder.from_pay_token(token)).to be_nil
      expect(mail.body.encoded).not_to include("This is a reminder")
    end

    it "adds the reminder paragraph when sent as a reminder" do
      described_class.send_job_quote(order.id, true).deliver_now
      expect(delivered.last.body.encoded).to include("This is a reminder that admins have approved a Job Order.")
    end

    it "switches to the re-approved wording once the order has more than one USER_APPROVAL row" do
      order.job_order_statuses.create!(job_status: JobStatus.user_approval, user: staff)
      described_class.send_job_quote(order.id).deliver_now
      expect(delivered.last.subject).to eq(
        "Votre commande ##{order.id} a été réapprouvée // Your job order ##{order.id} has been re-approved"
      )
    end

    # Money the customer reads before approving. The mail carries a French and
    # an English half; both must show the exact per-task prices (base fee +
    # parts fee), option and line-item prices and the grand total.
    # The `before` block's "Task #1" has no quote, so it also covers the
    # pending-price line.
    describe "quote amounts (multiple tasks, option price, line items)" do
      let(:text) do
        described_class.send_job_quote(order.id).deliver_now
        html = (delivered.last.html_part || delivered.last).body.decoded
        Nokogiri::HTML(html).text.gsub(/[[:space:]]+/, " ")
      end
      let(:french) { text.split("Hello,").first }
      let(:english) { "Hello," + text.split("Hello,").last }

      before { add_quoted_tasks!(order) }

      it "totals the quote to 58.50 (the fixture's arithmetic)" do
        expect(order.total_price).to eq(BigDecimal("58.5"))
      end

      it "shows the English per-task prices, option, line items and Grand Total" do
        expect(english).to include("- Print A : CAD $32.00 (base fee of $20.00 plus 4.0 unit × $3.00 )")
        expect(english).to include("• Polish : CAD $7.25")
        expect(english).to include("- Print B : CAD $15.50 (base fee of $15.50 plus 0.0 unit × $0.00 )")
        expect(english).to include("- Task #1 : Pending pricing")
        expect(english).to include("Line items: - Rush: CAD $2.50 - Setup: CAD $1.25")
        expect(english).to include("Grand Total: CAD $58.50")
      end

      it "shows the French per-task prices, option, line items and Total général" do
        expect(french).to include("- Print A : CAD $32.00 (frais de base de $20.00 plus 4.0 unité × $3.00 )")
        expect(french).to include("• Polish : CAD $7.25")
        expect(french).to include("- Print B : CAD $15.50 (frais de base de $15.50 plus 0.0 unité × $0.00 )")
        expect(french).to include("- Task #1 : Prix en attente")
        expect(french).to include("Articles détaillés : - Rush: CAD $2.50 - Setup: CAD $1.25")
        expect(french).to include("Total général : CAD $58.50")
      end
    end

    it "sends nothing for an unknown order" do
      described_class.send_job_quote(99_999_999).deliver_now
      expect(delivered).to be_empty
    end
  end

  describe ".send_job_declined" do
    it "mails the customer" do
      described_class.send_job_declined(order.id).deliver_now
      expect(delivered.last.to).to eq([owner.email])
      expect(delivered.last.subject).to eq("Your job ##{order.id} has been declined")
      expect(delivered.last.bcc).to eq(["uottawa.makerepo@gmail.com"])
    end
  end

  describe ".send_job_user_approval" do
    it "notifies the makerspace mailbox, with the EXPEDITED variant for expedited orders" do
      described_class.send_job_user_approval(order.id).deliver_now
      expect(delivered.last.subject).to eq("A user has approved a Job Order")

      expedite!
      described_class.send_job_user_approval(order.id).deliver_now
      expect(delivered.last.subject).to eq("EXPEDITED: A user has approved a Job Order")
      expect(delivered.last.header["X-Priority"].to_s).to eq("1")
    end
  end

  describe ".send_job_completed" do
    it "uses the default 'processed' message with the order id and quoted balance when no message is given" do
      order.job_tasks.first.build_job_task_quote(price: 12.5, service_price: 0, service_quantity: 0).save!
      described_class.send_job_completed(order.id, nil).deliver_now

      body = delivered.last.body.encoded
      expect(delivered.last.subject).to eq("Your Job Order ##{order.id} has been completed")
      expect(body).to include("Your print has completed and is now available for pickup!")
      expect(body).to include("Your order ID is #{order.id}")
      expect(body).to include("12.5")
    end

    it "sanitizes a custom message" do
      described_class.send_job_completed(order.id, "<p>All done</p><script>alert(1)</script>").deliver_now
      body = delivered.last.body.encoded
      expect(body).to include("All done")
      expect(body).not_to include("<script>")
    end
  end

  describe ".payment_succeeded" do
    it "payment_succeeded mails the customer the pickup notice" do
      described_class.payment_succeeded(order.id).deliver_now
      expect(delivered.last.to).to eq([owner.email])
      expect(delivered.last.subject).to eq("Your Job Order ##{order.id} is now ready for pickup")
      expect(delivered.last.bcc).to eq(["uottawa.makerepo@gmail.com"])
    end

    # WART(D-J31): the "View Order" button of the pickup mail links to the pay page,
    # which renders a 500 for orders that are already PAID.
    it "payment_succeeded links the order's pay page (a link that 500s once the order is PAID)" do
      described_class.payment_succeeded(order.id).deliver_now
      expect(delivered.last.body.decoded).to include("/job_orders/pay?token=")
    end
  end

  describe ".staff_assigned" do
    it "mails the assigned staff member (plain subject)" do
      described_class.staff_assigned(order.id, staff.id).deliver_now
      expect(delivered.last.to).to eq([staff.email])
      expect(delivered.last.subject).to eq("You've been assigned to Job Order ##{order.id}")
    end

    it "uses the EXPEDITED subject and priority headers for expedited orders" do
      expedite!
      described_class.staff_assigned(order.id, staff.id).deliver_now
      expect(delivered.last.subject).to eq("EXPEDITED: You've been assigned to Job Order ##{order.id}")
      expect(delivered.last.header["Importance"].to_s).to eq("high")
    end

    it "sends nothing for an unknown order" do
      described_class.staff_assigned(99_999_999, staff.id).deliver_now
      expect(delivered).to be_empty
    end
  end
end
