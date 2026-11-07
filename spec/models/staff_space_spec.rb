require "rails_helper"

RSpec.describe StaffSpace, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:space).without_validating_presence }
    end
  end

  describe "colour assignment" do
    let(:space) { create(:space) }

    it "keeps a colour passed on create" do
      first = create(:staff_space, space: space, color: "#123456")
      expect(first.reload.color).to eq("#123456")
    end

    it "gives a blank colour on create the first free palette entry" do
      expect(create(:staff_space, space: space, color: nil).color).to eq("#e6194b")
      expect(create(:staff_space, space: space, color: "").color).to eq("#3cb44b")
    end

    it "skips palette entries already taken in the space, including ones passed explicitly" do
      create(:staff_space, space: space, color: "#e6194b")
      expect(create(:staff_space, space: space, color: nil).color).to eq("#3cb44b")
    end

    it "hands out palette colours in order, per space" do
      colours = 3.times.map { create(:staff_space, space: space, color: nil).color }
      expect(colours).to eq(%w[#e6194b #3cb44b #ffe119])
      expect(create(:staff_space, space: create(:space), color: nil).color).to eq("#e6194b")
    end

    it "falls back to a colour derived from the user id when the palette is exhausted" do
      22.times { create(:staff_space, space: space, color: nil) }
      extra = create(:staff_space, space: space, color: nil)
      expect(extra.color).to match(/\A#\h{6}\z/)
      expect($color_list).not_to include(extra.color) if $color_list.none? { |c| c == extra.color }
    end

    it "keeps an explicit colour on update but regenerates a nil one" do
      ss = create(:staff_space, space: space, color: nil)
      ss.update!(color: "#abcdef")
      expect(ss.reload.color).to eq("#abcdef")
      ss.update!(color: nil)
      expect(ss.reload.color).to match(/\A#\h{6}\z/)
    end

    it "allows a StaffSpace without user or space (both optional)" do
      expect(StaffSpace.new).to be_valid
    end
  end
end
