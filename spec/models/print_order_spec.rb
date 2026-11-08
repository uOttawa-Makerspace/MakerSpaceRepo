require "rails_helper"

RSpec.describe PrintOrder, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
    end
  end

  describe "Active Storage" do
    it "keeps stored attachments reachable through the polymorphic record" do
      print_order = create(:print_order, :with_file)

      attachment = ActiveStorage::Attachment.find_by!(record_type: "PrintOrder", record_id: print_order.id, name: "file")

      expect(attachment.record).to eq(print_order)
      expect(PrintOrder.find(print_order.id).file).to be_attached
    end

    context "file type validation" do
      it "should be false" do
        print_order = build(:print_order, :with_invalid_file)
        expect(print_order.valid?).to be_falsey
      end

      it "should be true" do
        print_order = build(:print_order, :with_file)
        expect(print_order.valid?).to be_truthy
      end
    end

    context "final_file type validation" do
      it "should be false" do
        print_order = build(:print_order, :with_invalid_final_file)
        expect(print_order.valid?).to be_falsey
      end

      it "should be true" do
        print_order = build(:print_order, :with_final_file)
        expect(print_order.valid?).to be_truthy
      end
    end

    context "team pdf type validation" do
      it "should be false" do
        print_order = build(:print_order, :with_invalid_final_file)
        expect(print_order.valid?).to be_falsey
      end

      it "should be true" do
        print_order = build(:print_order, :with_final_file)
        expect(print_order.valid?).to be_truthy
      end
    end
  end

  describe "after_save" do
    context "#set_filename" do
      it "should change the filename" do
        print_order = create(:print_order, :with_file)
        expect(PrintOrder.last.file.filename).to eq(
          "#{print_order.id}_test.stl"
        )
      end
    end
  end
end
