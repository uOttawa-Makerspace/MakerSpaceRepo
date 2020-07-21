require 'rails_helper'

RSpec.describe Video, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:proficient_project) }
    end

    context 'has_one_attached' do
      it "has video attached" do
        video = create(:video, :with_video)
        expect(video.video).to be_attached
      end

      it 'invalid image attached' do
        video = build(:video, :with_invalid_video)
        expect(video.valid?).to be_falsey
      end
    end
  end

  describe 'Scopes' do
    before(:each) do
      3.times{ create(:video, processed: true) }
      4.times{ create(:video) }
    end

    context '#processed' do
      it 'should return processed videos' do
        expect(Video.processed.count).to eq(3)
      end
    end
  end
end
