require 'rails_helper'

RSpec.describe JobOrderOption, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:job_order) }
      it { should belong_to(:job_option) }
    end
  end

  describe 'Active Storage' do
    context 'file type validation' do
      it 'should be false' do
        job_order_option = build(:job_order_option, :with_invalid_option_file)
        expect(job_order_option.valid?).to be_falsey
      end

      it 'should be true' do
        job_order_option = build(:job_order_option, :with_option_file)
        expect(job_order_option.valid?).to be_truthy
      end
    end
  end
end
