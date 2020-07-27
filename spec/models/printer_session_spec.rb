require 'rails_helper'

RSpec.describe PrinterSession, type: :model do

  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:printer) }
      it { should belong_to(:user) }
    end

  end

end
