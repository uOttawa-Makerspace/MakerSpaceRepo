require "rails_helper"

RSpec.describe Setting, type: :model do
  it "requires a key" do
    expect(Setting.new(value: "x")).not_to be_valid
  end

  it "requires a unique key" do
    Setting.create!(key: "k", value: "1")
    dup = Setting.new(key: "k", value: "2")
    expect(dup).not_to be_valid
    expect(dup.errors[:key]).to include("has already been taken")
  end

  describe ".get / .set" do
    it "returns nil for an unknown key" do
      expect(Setting.get("missing")).to be_nil
    end

    it "creates then updates in place" do
      expect { Setting.set("k", "1") }.to change(Setting, :count).by(1)
      expect(Setting.get("k")).to eq("1")
      expect { Setting.set("k", "2") }.not_to change(Setting, :count)
      expect(Setting.get("k")).to eq("2")
    end

    it "returns the setting record" do
      expect(Setting.set("k", "v")).to be_a(Setting).and have_attributes(key: "k", value: "v")
    end
  end

  describe "maintenance email" do
    it "round-trips through the maintenance_notification_email key" do
      expect(Setting.maintenance_email).to be_nil
      Setting.maintenance_email = "ops@example.test"
      expect(Setting.maintenance_email).to eq("ops@example.test")
      expect(Setting.get("maintenance_notification_email")).to eq("ops@example.test")
    end
  end
end
