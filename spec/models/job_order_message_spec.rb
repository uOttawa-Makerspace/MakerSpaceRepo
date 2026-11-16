require "rails_helper"

RSpec.describe JobOrderMessage, type: :model do
  describe "Validations" do
    context "presence" do
      it { should validate_presence_of(:name) }
      it { should validate_uniqueness_of(:name) }
      it { should validate_presence_of(:message) }
    end
  end

  describe "#retrieve_message" do
    include JobOrderSpecHelpers

    let(:template) { "Order [PRINT_ID] owes [QUOTED_BALANCE]; again [PRINT_ID]." }
    let(:record) { described_class.create!(name: "processed", message: template) }
    let(:owner) { create(:user, :regular_user) }

    before { seed_job_statuses! }

    it "fills in the order id and quoted balance" do
      order = make_job_order!(owner: owner, status_key: :user_approval)
      balance = ActiveSupport::NumberHelper.number_to_currency(order.total_price)

      expect(record.retrieve_message(order.id))
        .to eq("Order #{order.id} owes #{balance}; again #{order.id}.")
    end

    it "leaves the stored text and the record untouched" do
      order = make_job_order!(owner: owner, status_key: :user_approval)

      record.retrieve_message(order.id)

      expect(record.message).to eq(template)
      expect(record).not_to be_changed
      expect(record.reload.message).to eq(template)
    end

    it "fills each order's own id when the same record is used for two orders" do
      first = make_job_order!(owner: owner, status_key: :user_approval)
      second = make_job_order!(owner: owner, status_key: :user_approval)

      record.retrieve_message(first.id)

      expect(record.retrieve_message(second.id)).to start_with("Order #{second.id} owes")
    end

    it "looks the order up once" do
      order = make_job_order!(owner: owner, status_key: :user_approval)
      selects = []
      counter = lambda do |*, payload|
        selects << payload[:sql] if payload[:sql].match?(/FROM "job_orders"/)
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        record.retrieve_message(order.id)
      end

      expect(selects.size).to eq(1)
    end

    it "raises when the order does not exist" do
      expect { record.retrieve_message(0) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
