# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categorizable, type: :model do
  let(:owner) { create(:user, :regular_user) }
  let(:repository) { create(:repository, owner: owner, title: "Laser Lamp", users: [owner]) }

  before { Category.create!(name: "Old", repository: repository) }

  describe "#update_with_categories" do
    it "saves the edit and replaces the categories with the names given" do
      expect(repository.update_with_categories({ title: "Renamed" }, %w[New Newer])).to be(true)
      expect(repository.reload.title).to eq("Renamed")
      expect(repository.categories.pluck(:name)).to match_array(%w[New Newer])
    end

    it "clears the categories for an empty list" do
      expect(repository.update_with_categories({ title: "Renamed" }, [])).to be(true)
      expect(repository.reload.categories).to be_empty
    end

    it "changes nothing when the edit is refused" do
      expect(repository.update_with_categories({ title: "" }, %w[New])).to be(false)
      expect(repository.reload.title).to eq("Laser Lamp")
      expect(repository.categories.pluck(:name)).to eq(["Old"])
    end

    it "rolls the edit back when a category cannot be stored" do
      allow_any_instance_of(Category).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
      expect { repository.update_with_categories({ title: "Renamed" }, %w[New]) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(repository.reload.title).to eq("Laser Lamp")
      expect(repository.categories.pluck(:name)).to eq(["Old"])
    end
  end

  describe "#replace_categories" do
    it "skips blank names and keeps only the first five" do
      repository.replace_categories(["", "a", nil, "b", "c", "d", "e", "f"])
      expect(repository.reload.categories.pluck(:name)).to match_array(%w[a b c d e])
    end

    it "works the same for a project proposal" do
      proposal = create(:project_proposal, user: owner)
      proposal.replace_categories(%w[Robots])
      expect(proposal.reload.categories.pluck(:name)).to eq(["Robots"])
    end
  end
end
