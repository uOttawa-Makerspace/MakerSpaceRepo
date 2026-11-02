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
      it "returns a completed order's stored subtotal, not a re-pricing of its items" do
        order_item = create(:order_item) # on a completed order whose stored subtotal is 50
        expect(order_item.order.reload.subtotal).to eq(50)
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
# ---- Chunk 8 characterization (shop): money math and state ------------------
RSpec.describe Order, type: :model do
  let(:user) { create(:user, :regular_user) }

  def add_item(order, cc, quantity: 1)
    order.order_items.create!(proficient_project: create(:proficient_project, cc: cc), quantity: quantity)
  end

  describe "status constants (seeded OrderStatus rows)" do
    it "ships exactly the two seeded statuses the app looks up by name" do
      expect(OrderStatus.order(:id).pluck(:name)).to eq(["In progress", "Completed"])
    end
  end

  describe "creation defaults" do
    it "defaults the status to 'In progress' when none is given" do
      order = Order.create!(user: user)
      expect(order.order_status.name).to eq("In progress")
      expect(order.completed?).to be(false)
    end

    it "keeps an explicitly given status" do
      order = Order.create!(user: user, order_status: OrderStatus.find_by!(name: "Completed"))
      expect(order.completed?).to be(true)
    end

    it "allows no user (guest cart)" do
      expect(Order.new).to be_valid
    end

    it "prices an empty cart (new or saved) at 0" do
      expect(Order.new.subtotal).to eq(0)
      expect(Order.create!.reload.subtotal).to eq(0)
    end
  end

  describe "#subtotal (live for an open cart, stored for any other order)" do
    it "sums quantity * unit_price over the items" do
      order = Order.create!(user: user)
      add_item(order, 10, quantity: 2)
      add_item(order, 15)
      expect(order.reload.subtotal).to eq(35)
    end

    it "never writes the subtotal column for an open cart (saving it writes nothing; only checkout! stores it)" do
      order = Order.create!(user: user)
      add_item(order, 10)
      order.save!
      expect(order.reload[:subtotal]).to be_nil
      expect(order.subtotal).to eq(10)
    end

    it "has no total while an item can no longer be bought (never counts it as 0)" do
      order = Order.create!(user: user)
      add_item(order, 15)
      item = add_item(order, 10)
      item.update_column(:quantity, 0)
      expect(order.reload.subtotal).to be_nil
      expect(order.checkout_lines).to be_nil
    end

    it "is ONE pricing: the cart total, the pre-check total and the charge agree; checkout stores it once" do
      order = Order.create!(user: user)
      add_item(order, 10, quantity: 2)
      add_item(order, 15)
      lines, total = order.checkout_lines
      expect(total).to eq(35)
      expect(lines.sum(&:last)).to eq(35)
      expect(order.subtotal).to eq(35)
      CcMoney.create!(user: user, cc: 100)
      expect(Order.checkout!(order, user).first).to eq(:completed)
      expect(order.reload[:subtotal]).to eq(35)
      expect(order.total).to eq(35)
    end

    it "shows a completed order's stored subtotal (the amount charged), never re-priced" do
      order = Order.create!(user: user)
      item = add_item(order, 10)
      CcMoney.create!(user: user, cc: 100)
      Order.checkout!(order, user)
      item.update_column(:quantity, 0) # now invalid: re-pricing would say nil
      item.proficient_project.update!(cc: 99)
      completed = Order.find(order.id)
      expect(completed.subtotal).to eq(10)
      expect(completed.total).to eq(10)
    end

    it "uses the item's frozen unit_price, not the project's live cc" do
      order = Order.create!(user: user)
      item = add_item(order, 10)
      item.proficient_project.update!(cc: 99)
      expect(order.reload.subtotal).to eq(10)
    end
  end

  describe "#completed?" do
    it "raises for an order without a status row (NoMethodError on nil)" do
      order = Order.create!(user: user)
      order.update_column(:order_status_id, nil)
      expect { order.reload.completed? }.to raise_error(NoMethodError)
    end
  end

  describe "dependent destroy" do
    it "destroys items and cc_moneys with the order, but not the user's other cc_moneys" do
      order = Order.create!(user: user)
      add_item(order, 10)
      CcMoney.create!(user: user, cc: -10, order: order)
      kept = CcMoney.create!(user: user, cc: 5)
      expect { order.destroy }.to change(OrderItem, :count).by(-1).and change(CcMoney, :count).by(-1)
      expect(CcMoney.exists?(kept.id)).to be(true)
    end
  end

  describe ".completed scope" do
    it "joins on the status name (case-sensitive 'Completed')" do
      create(:order)
      done = create(:order, :completed)
      expect(Order.completed).to contain_exactly(done)
    end
  end
end

RSpec.describe OrderItem, "project is fixed once created", type: :model do
  it "cannot change proficient_project_id on a persisted item, by any path" do
    order = Order.create!(user: create(:user, :regular_user))
    item = order.order_items.create!(proficient_project: create(:proficient_project, cc: 10), quantity: 1)
    other = create(:proficient_project, cc: 400)
    expect { item.update(proficient_project_id: other.id) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    expect { item.update_column(:proficient_project_id, other.id) }.to raise_error(ActiveRecord::ActiveRecordError)
    expect(item.reload.proficient_project_id).not_to eq(other.id)
  end
end
