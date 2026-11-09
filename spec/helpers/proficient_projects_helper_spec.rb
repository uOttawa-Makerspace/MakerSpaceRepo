# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProficientProjectsHelper, type: :helper do
  describe "#training_status" do
    let(:training) { create(:training) }
    let(:user) { create(:user) }

    it "marks a user who has not started with the muted text class and no inline colour" do
      html = helper.training_status(training.id, user.id)

      expect(html).to include("Not Started")
      expect(html).to include("text-body-secondary")
      expect(html).not_to include("style=")
    end

    it "marks a user who has started with the body text class and no inline colour" do
      project = create(:proficient_project, training: training)
      create(:order_item, :awarded, proficient_project: project, order: create(:order, user: user))
      html = helper.training_status(training.id, user.id)

      expect(html).to include("Newbie")
      expect(html).to include("text-body")
      expect(html).not_to include("style=")
    end
  end
end
