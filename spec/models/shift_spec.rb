require "rails_helper"

RSpec.describe Shift, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:space).without_validating_presence }
    end

    context "has_and_belongs_to_many" do
      it { should have_and_belong_to_many(:users) }
    end
  end

  describe "Validations" do
    context "start_datetime" do
      it { should validate_presence_of(:start_datetime) }
    end

    context "end_datetime" do
      it { should validate_presence_of(:end_datetime) }
    end
  end

  describe "Methods" do
    context "event_title" do
      it "should return the title of the shift" do
        user = create(:user, name: "John Doe")
        shift = create(:shift, users: [user], reason: "Test Reason")
        expect(shift.return_event_title).to eq("Test Reason for John Doe")
      end
    end

    context "color" do
      it "should return color for single user" do
        staff_space = create(:staff_space)
        StaffSpace.find(staff_space.id).update(color: "#0099ff")
        shift =
          create(:shift, users: [staff_space.user], space: staff_space.space)
        expect(shift.color(staff_space.space_id, 1)).to eq(
          "rgba(0, 153, 255, 1)"
        )
      end

      it "should return color for single user but transparent" do
        staff_space = create(:staff_space)
        StaffSpace.find(staff_space.id).update(color: "#0099ff")
        shift =
          create(:shift, users: [staff_space.user], space: staff_space.space)
        expect(shift.color(staff_space.space_id, 0.7)).to eq(
          "rgba(0, 153, 255, 0.7)"
        )
      end

      it "should return color for multi user" do
        space = create(:space)
        staff_space1 = create(:staff_space, space: space)
        StaffSpace.find(staff_space1.id).update(color: "#000000")
        staff_space2 = create(:staff_space, space: space)
        StaffSpace.find(staff_space2.id).update(color: "#ffffff")
        shift =
          create(
            :shift,
            users: [staff_space1.user, staff_space2.user],
            space: space
          )
        expect(shift.color(space.id, 1)).to eq(
          "linear-gradient(to right, rgba(0, 0, 0, 1) 0% 50%, rgba(255, 255, 255, 1) 50% 100%)"
        )
      end
    end
  end
end
