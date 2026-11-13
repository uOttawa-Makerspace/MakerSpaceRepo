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

  describe "colour format" do
    let(:space) { create(:space) }

    it "accepts a #rrggbb value in either case and stores it lower case" do
      expect(create(:staff_space, space: space, color: "#ABCDEF").reload.color).to eq("#abcdef")
    end

    ["red", "#fff", "#12345", "#1234567", "red;background:url(x)", "#ff0000;x", "url(x)"].each do |bad|
      it "rejects #{bad.inspect}" do
        staff_space = build(:staff_space, space: space, color: bad)
        expect(staff_space).not_to be_valid
        expect(staff_space.errors[:color]).to be_present
      end
    end

    it "treats an upper case colour as the palette colour it spells when picking a free one" do
      create(:staff_space, space: space, color: "#E6194B")
      expect(create(:staff_space, space: space, color: nil).color).to eq("#3cb44b")
    end

    it "leaves a stored value that no longer matches alone while other fields change" do
      staff_space = create(:staff_space, space: space)
      staff_space.update_column(:color, "red") # rubocop:disable Rails/SkipsModelValidations
      expect(staff_space.reload.update(user: create(:user))).to be(true)
      expect(staff_space.reload.color).to eq("red")
      expect(staff_space.update(color: "blue")).to be(false)
    end
  end
end

RSpec.describe StaffSpace, "calendar staff of a space", type: :model do
  let(:space) { create(:space) }
  let!(:zed) { create(:staff_space, space: space, color: "#111111", user: create(:user, :staff, name: "zed")).user }
  let!(:amy) { create(:staff_space, space: space, color: "#222222", user: create(:user, :admin, name: "Amy")).user }
  let!(:bea) { create(:staff_space, space: space, color: "#333333", user: create(:user, :staff, name: "Bea")).user }

  before do
    create(:staff_space, space: space, user: create(:user, :regular_user))
    create(:staff_space, space: create(:space), user: create(:user, :staff))
  end

  it "gives each member's colour by user id" do
    expect(described_class.colors_in(space.id)).to include(zed.id => "#111111", amy.id => "#222222")
    expect(described_class.colors_in(0)).to eq({})
  end

  it "lists the space's staff and admins only" do
    expect(described_class.calendar_staff(space.id)).to contain_exactly(zed, amy, bea)
  end

  it "lists the sidebar staff with unavailabilities first, each part by name" do
    create(:staff_unavailability, user: zed)
    StaffExternalUnavailability.create!(user: bea, ics_url: "https://calendar.example/bea.ics")

    expect(described_class.calendar_sidebar(space.id)).to eq([
      { id: bea.id, name: "Bea", color: "#333333", busy: true },
      { id: zed.id, name: "zed", color: "#111111", busy: true },
      { id: amy.id, name: "Amy", color: "#222222", busy: false }
    ])
  end
end
