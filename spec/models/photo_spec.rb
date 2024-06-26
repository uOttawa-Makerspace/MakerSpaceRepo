require "rails_helper"

RSpec.describe Photo, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:repository).without_validating_presence }
      it { should belong_to(:proficient_project).without_validating_presence }
      it { should belong_to(:project_proposal).without_validating_presence }
    end

    context "has_one_attached" do
      it "has video attached" do
        photo = create(:photo)
        expect(photo.image).to be_attached
      end

      it "invalid image attached" do
        photo = build(:photo, :with_invalid_image)
        expect(photo.valid?).to be_falsey
      end
    end
  end
end
