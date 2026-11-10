require "rails_helper"

RSpec.describe OrderItem, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:proficient_project).without_validating_presence }
      it { should belong_to(:order).without_validating_presence }
    end
  end

  describe "Validations" do
    context "quantity" do
      it { should validate_presence_of(:quantity) }
      it do
        should validate_numericality_of(:quantity).only_integer.is_greater_than(
                 0
               )
      end
    end

    context "product_present" do
      it "should validate product present (true)" do
        order_item = build(:order_item)
        expect(order_item.valid?).to be_truthy
      end

      it "should validate product present (false)" do
        order_item = build(:order_item, proficient_project_id: "")
        expect(order_item.valid?).to be_falsey
      end
    end

    context "order_present" do
      it "should validate the order present (true)" do
        order_item = build(:order_item)
        expect(order_item.valid?).to be_truthy
      end

      it "should validate the order present (false)" do
        order_item = build(:order_item, order_id: "")
        expect(order_item.valid?).to be_falsey
      end
    end
  end

  describe "before_save" do
    context "finalize" do
      it "should set the unit price and quantity" do
        order_item = build(:order_item, quantity: 2)
        order_item.save
        expect(OrderItem.last.unit_price).to eq(10.0)
        expect(OrderItem.last.total_price).to eq(20.0)
      end
    end
  end
end

# ---- Chunk 8 characterization (shop) ---------------------------------------
RSpec.describe OrderItem, type: :model do
  let(:order) { create(:order) }
  let(:project) { create(:proficient_project, cc: 12) }

  describe "#unit_price / #total_price" do
    it "reads the project's cc while unsaved" do
      item = order.order_items.new(proficient_project: project, quantity: 3)
      expect(item.unit_price).to eq(12)
      expect(item.total_price).to eq(36)
    end

    it "freezes the price at first save and ignores later project price changes" do
      item = order.order_items.create!(proficient_project: project, quantity: 2)
      project.update!(cc: 50)
      item.reload
      expect([item.unit_price, item.total_price]).to eq([12, 24])
      item.update!(quantity: 4)
      expect([item.unit_price, item.total_price]).to eq([12, 48])
    end

    it "stores decimals with 3 digits and the default status" do
      item = order.order_items.create!(proficient_project: project, quantity: 1)
      expect(item.reload.unit_price).to be_a(BigDecimal)
      expect(item.status).to eq("In progress")
    end

    it "raises (NoMethodError) asking the price of an unsaved item with no project" do
      expect { OrderItem.new(quantity: 1).unit_price }.to raise_error(NoMethodError)
    end
  end

  describe "validations (custom messages)" do
    it "requires a project and an order" do
      item = OrderItem.new(quantity: 1)
      expect(item).not_to be_valid
      expect(item.errors[:proficient_project]).to eq(["is not valid"])
      expect(item.errors[:order]).to eq(["is not a valid order."])
    end

    it "rejects non-integer and non-positive quantities" do
      [0, -1, 1.5].each do |q|
        item = order.order_items.new(proficient_project: project, quantity: q)
        expect(item).not_to be_valid
        expect(item.errors[:quantity]).to be_present
      end
    end
  end

  describe "scopes" do
    it "filters by item status and by completed order" do
      done = create(:order, :completed)
      a = create(:order_item, order: done, status: "Awarded")
      b = create(:order_item, order: order, status: "In progress")
      c = create(:order_item, order: order, status: "Waiting for approval")
      expect(OrderItem.awarded).to contain_exactly(a)
      expect(OrderItem.in_progress).to contain_exactly(b)
      expect(OrderItem.waiting_for_approval).to contain_exactly(c)
      expect(OrderItem.completed_order).to contain_exactly(a)
    end
  end

  describe "revoking and awarding a project badge" do
    let(:staff) { create(:user, :staff) }
    let(:buyer) { create(:user) }
    let(:item) do
      create(:order_item, order: create(:order, :completed, user_id: buyer.id), status: "Waiting for approval")
    end

    it "deactivates the granted certification on revoke and restores it on award, in both directions repeatably" do
      expect(item.award!(staff, admin_comments: "ok")).to be(true)
      cert = Certification.find_by!(user_id: buyer.id)

      2.times { expect(item.revoke!(staff)).to be(true) }
      expect(item.reload.status).to eq("Revoked")
      expect(Certification.unscoped.find(cert.id)).not_to be_active
      expect(Certification.unscoped.where(user_id: buyer.id).count).to eq(1)

      expect(item.award!(staff)).to be(true)
      expect(item.award!(staff)).to be(false)
      expect(Certification.find(cert.id)).to be_active
      expect(ProficientProjectSession.count).to eq(1)
    end

    it "does not award an item that is not waiting and has no deactivated badge" do
      item.update!(status: "In progress")
      expect(item.award!(staff)).to be(false)
      expect(Certification.unscoped.count).to eq(0)
    end

    it "reports false and writes nothing when the revoke does not save" do
      allow(item).to receive(:update).and_return(false)
      expect(item.revoke!(staff)).to be(false)
      expect(item.reload.status).to eq("Waiting for approval")
    end
  end
end
