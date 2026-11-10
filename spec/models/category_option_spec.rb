require "rails_helper"

RSpec.describe CategoryOption, type: :model do
  describe "Association" do
    context "has_many" do
      it { should have_many(:categories) }
    end
  end

  describe "#in_use?" do
    it "is true only while a category points at the option" do
      option = create(:category_option)
      expect(option.in_use?).to be(false)
      create(:category, category_option: option)
      expect(option.in_use?).to be(true)
    end
  end

  describe "Validations" do
    context "presence" do
      it { should validate_presence_of(:name) }
    end
  end

  describe "Scopes" do
    context "show_options" do
      it "should order all equipment options" do
        first_category_option =
          create(:category_option, name: "a as first letter")
        last_category_option =
          create(:category_option, name: "z as first letter")
        middle_category_option =
          create(:category_option, name: "f as first letter")
        expect(CategoryOption.show_options.count).to eq(3)
        expect(CategoryOption.show_options.pluck(:name)).to eq(
          [
            first_category_option.name,
            middle_category_option.name,
            last_category_option.name
          ]
        )
      end
    end
  end
end
