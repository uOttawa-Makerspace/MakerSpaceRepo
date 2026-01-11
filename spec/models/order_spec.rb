require "rails_helper"

RSpec.describe Order, type: :model do
  describe "Association" do
    subject { create(:order) }

    context "has_many" do
      it { should have_many(:order_items) }
      it { should have_many(:proficient_projects) }
      it { should have_many(:cc_moneys) }
    end

    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:order_status).without_validating_presence }
    end
  end

  describe "#before_validation" do
    context "set_order_status" do
      it "should set the order status" do
        order = create(:order)
        expect(order.order_status.name).to eq("In progress")
      end
    end
  end

  describe "#scopes" do
    context "completed" do
      it "should return only completed orders" do
        create_list(:order, 2)
        create_list(:order, 2, :completed)
        expect(Order.completed.count).to eq(2)
      end
    end
  end

  describe "model methods" do
    context "#subtotal" do
      it "should calculate the subtotal" do
        order_item = create(:order_item)
        expect(order_item.order.reload.subtotal).to eq(10)
      end
    end

    context "#completed?" do
      it "should check if the order is completed (true)" do
        order = create(:order, :completed)
        expect(order.completed?).to be_truthy
      end

      it "should check if the order is completed (false)" do
        order = create(:order)
        expect(order.completed?).to be_falsey
      end
    end
  end
end