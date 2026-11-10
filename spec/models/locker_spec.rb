# frozen_string_literal: true

require "rails_helper"

RSpec.describe Locker do
  describe ".order_by_specifier" do
    it "orders numeric specifiers by number and puts other names after them" do
      size = create(:locker_size)
      %w[10 2 B-1 100 1 A-2].each { |s| create(:locker, specifier: s, locker_size: size) }
      expect(described_class.order_by_specifier.pluck(:specifier)).to eq(%w[1 2 10 100 A-2 B-1])
    end
  end

  describe ".sort_specifiers" do
    it "sorts numbers by value, then other names as text" do
      expect(described_class.sort_specifiers(%w[10 2 B 1 A])).to eq(%w[1 2 10 A B])
    end
  end
end
