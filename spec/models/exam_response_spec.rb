require 'rails_helper'

RSpec.describe ExamResponse, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:answer) }
      it { should belong_to(:exam_question) }
    end

    context 'has_one' do
      it { should have_one(:exam) }
      it { should have_one(:user) }
    end
  end
end
