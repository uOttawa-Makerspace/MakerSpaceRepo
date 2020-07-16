require 'rails_helper'

RSpec.describe Order, type: :model do

  describe 'Association' do

    context 'has_many' do
      it { should have_many(:order_items) }
      it { should have_many(:proficient_projects) }
      it { should have_many(:cc_moneys) }
    end

    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:order_status) }
    end

  end

  describe "#before_validation" do

    context "set_order_status" do

      it 'should set the order status' do
        OrderStatus.create(name: "In progress")
        create(:order)
        expect(Order.last.order_status_id).to eq(1)
      end

    end

  end

  describe "#scopes" do

    context "completed" do

      it 'should set the order status' do
        OrderStatus.create(name: "In progress")
        OrderStatus.create(name: "Completed")
        create(:order)
        create(:order)
        create(:order, :completed)
        create(:order, :completed)
        expect(Order.completed.count).to eq(2)
      end

    end

  end

  describe "model methods" do

    context "#subtotal" do

      it 'should calculate the subtotal' do
        OrderStatus.create(name: "In progress")
        OrderStatus.create(name: "Completed")
        create(:order_item)
        expect(Order.last.subtotal).to eq(10) # 10 because the PP CC is 10
      end

    end

    context "#completed?" do

      before(:each) do
        OrderStatus.create(name: "In progress")
        OrderStatus.create(name: "Completed")
      end

      it 'should check if the order is completed (true)' do
        create(:order, :completed)
        expect(Order.last.completed?).to be_truthy
      end

      it 'should check if the order is completed (false)' do
        create(:order)
        expect(Order.last.completed?).to be_falsey
      end

    end

  end

end
