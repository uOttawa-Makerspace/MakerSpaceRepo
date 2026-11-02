require "rails_helper"

RSpec.describe QuickAccessLink, type: :model do
  let(:user) { create(:user, :admin) }

  it { should belong_to(:user) }

  it "is valid with a name and a routable path" do
    expect(QuickAccessLink.new(user: user, name: "Home", path: "/")).to be_valid
    expect(QuickAccessLink.new(user: user, name: "Faq", path: "/faq")).to be_valid
  end

  it "requires name and path" do
    link = QuickAccessLink.new(user: user, name: "", path: "")
    expect(link).not_to be_valid
    expect(link.errors[:name]).to be_present
    expect(link.errors[:path]).to be_present
  end

  it "rejects a path that does not route" do
    link = QuickAccessLink.new(user: user, name: "Bad", path: "/no/such/route/at/all/xyz")
    expect(link).not_to be_valid
    expect(link.errors[:path]).to include("must be a valid path")
  end

  it "rejects a path pointing at a user profile" do
    link = QuickAccessLink.new(user: user, name: "Me", path: "/#{user.username}")
    expect(link).not_to be_valid
    expect(link.errors[:path]).to include("cannot point to a user")
  end

  it "is unique per user and path, but two users may share a path" do
    QuickAccessLink.create!(user: user, name: "Home", path: "/")
    dup = QuickAccessLink.new(user: user, name: "Again", path: "/")
    expect(dup).not_to be_valid
    expect(dup.errors[:path]).to include("You already have a quick access link to that location")
    expect(QuickAccessLink.new(user: create(:user, :admin), name: "Home", path: "/")).to be_valid
  end
end
