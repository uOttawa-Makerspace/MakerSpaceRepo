require 'rails_helper'

RSpec.describe RepoFile, type: :model do

  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:repository) }
      it { should belong_to(:proficient_project) }
    end

  end

  describe "Validation" do

    context 'has_one_attached' do
      it "has file attached" do
        file = create(:repo_file)
        expect(file.file).to be_attached
      end

      it 'valid file attached for repo' do
        file = build(:repo_file, :in_repository, :with_invalid_file)
        expect(file.valid?).to be_falsey
      end

      it 'has invalid file attached' do
        file = build(:repo_file, :in_proficient_project, :with_invalid_file)
        expect(file.valid?).to be_falsey
      end

    end

  end

end
