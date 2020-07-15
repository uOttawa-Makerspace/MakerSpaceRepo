require 'rails_helper'

RSpec.describe Category, type: :model do

  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:repository) }
      it { should belong_to(:category_option) }
      it { should belong_to(:project_proposal) }
    end

  end

end
