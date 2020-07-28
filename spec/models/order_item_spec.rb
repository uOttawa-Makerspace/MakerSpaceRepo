require 'rails_helper'

RSpec.describe OrderItem, type: :model do

  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:proficient_project) }
      it { should belong_to(:order) }
    end

  end

  describe "Validations" do

    context "quantity" do
      it { should validate_presence_of(:quantity) }
      it { should validate_numericality_of(:quantity).only_integer.is_greater_than(0) }
    end

    context "product_present" do

      it 'should validate product present (true)' do
        order_item = build(:order_item)
        expect(order_item.valid?).to be_truthy
      end

      it 'should validate product present (false)' do
        order_item = build(:order_item, proficient_project_id: "")
        expect(order_item.valid?).to be_falsey
      end

    end

    context 'order_present' do

      it 'should validate the order present (true)' do
        order_item = build(:order_item)
        expect(order_item.valid?).to be_truthy
      end

      it 'should validate the order present (false)' do
        order_item = build(:order_item, order_id: "")
        expect(order_item.valid?).to be_falsey
      end

    end

  end

  describe "before_save" do

    context "finalize" do

      it 'should set the unit price and quantity' do
        order_item = build(:order_item, quantity: 2)
        order_item.save
        expect(OrderItem.last.unit_price).to eq(10.0)
        expect(OrderItem.last.total_price).to eq(20.0)
      end

    end
    
  end

end
