# frozen_string_literal: true

require "rails_helper"

RSpec.describe Locker do
  describe ".order_by_specifier" do
    it "orders numeric specifiers by number and puts other names after them" do
      size = create(:locker_size)
      %w[10 2 B-1 100 1 A-2].each { |s| create(:locker, specifier: s, locker_size: size) }
      expect(described_class.order_by_specifier.pluck(:specifier)).to eq(%w[1 2 10 100 A-2 B-1])
    end

    it "puts a locker without a specifier last" do
      size = create(:locker_size)
      create(:locker, specifier: "B-1", locker_size: size)
      create(:locker, specifier: "2", locker_size: size)
      blank = create(:locker, locker_size: size)
      blank.update_column(:specifier, nil)
      expect(described_class.order_by_specifier.pluck(:specifier)).to eq(["2", "B-1", nil])
    end
  end

  describe ".sort_specifiers" do
    it "sorts numbers by value, then other names as text" do
      expect(described_class.sort_specifiers(%w[10 2 B 1 A])).to eq(%w[1 2 10 A B])
    end

    it "puts a missing specifier last, like the database order" do
      expect(described_class.sort_specifiers(["B", nil, "2"])).to eq(["2", "B", nil])
    end
  end
end
