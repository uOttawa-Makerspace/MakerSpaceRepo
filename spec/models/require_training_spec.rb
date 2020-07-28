require 'rails_helper'

RSpec.describe RequireTraining, type: :model do
  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:training) }
      it { should belong_to(:volunteer_task) }
    end

  end

  describe "Validations" do

    context 'password private' do
      it { should validate_presence_of(:training_id).with_message("A training must be selected") }
    end

  end

end
