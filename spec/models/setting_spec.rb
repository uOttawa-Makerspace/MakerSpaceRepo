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

  describe ".chat_extra_recipients" do
    it "defaults to users 25 and 1607 until the setting is saved" do
      expect(Setting.chat_extra_recipients).to eq(%w[25 1607])
    end

    it "splits ids and addresses on commas, spaces and new lines" do
      Setting.set(Setting::CHAT_EXTRA_RECIPIENTS_KEY, "7, a@example.com\nb@example.com  9")
      expect(Setting.chat_extra_recipients).to eq(%w[7 a@example.com b@example.com 9])
    end

    it "is empty when saved empty" do
      Setting.set(Setting::CHAT_EXTRA_RECIPIENTS_KEY, "")
      expect(Setting.chat_extra_recipients).to eq([])
    end
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

  describe ".claim" do
    it "is true for the first caller and false for a repeat with the same value" do
      expect(Setting.claim("run", "2026-11")).to be(true)
      expect(Setting.claim("run", "2026-11")).to be(false)
      expect(Setting.get("run")).to eq("2026-11")
    end

    it "is true again for a different value" do
      Setting.claim("run", "2026-11")
      expect(Setting.claim("run", "2026-12")).to be(true)
      expect(Setting.get("run")).to eq("2026-12")
    end

    it "is true again for the same value when forced" do
      Setting.claim("run", "2026-11")
      expect(Setting.claim("run", "2026-11", force: true)).to be(true)
    end

    it "keeps one row per key" do
      2.times { Setting.claim("run", "2026-11") }
      expect(Setting.where(key: "run").count).to eq(1)
    end
  end
end
