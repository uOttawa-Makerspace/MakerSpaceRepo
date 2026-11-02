require "rails_helper"

RSpec.describe OrderStatus, type: :model do
  describe "Association" do
    context "has_many" do
      it { should have_many(:orders) }
    end
  end
end

RSpec.describe OrderStatus, type: :model do
  it "has no validations: a nameless status is accepted" do
    expect { OrderStatus.create!(name: nil) }.not_to raise_error
  end

  it "the seeded rows are the lookups the app depends on" do
    expect(OrderStatus.find_by(name: "In progress")).to be_present
    expect(OrderStatus.find_by(name: "Completed")).to be_present
  end
end
