require "rails_helper"

RSpec.describe Printer, type: :model do
  before(:each) do
    @pt_1 = create(:printer_type, :Random)
    @pt_2 = create(:printer_type, :Random)
    @pt_3 = create(:printer_type, :Random)
    @pt_4 = create(:printer_type, :Random)

    @pt_1_1 = create(:printer, number: "1", printer_type_id: @pt_1.id)
    @pt_1_2 = create(:printer, number: "2", printer_type_id: @pt_1.id)
    @pt_2_1 = create(:printer, number: "1", printer_type_id: @pt_2.id)
    @pt_3_1 = create(:printer, number: "1", printer_type_id: @pt_3.id)
    @pt_3_2 = create(:printer, number: "2", printer_type_id: @pt_3.id)
    @pt_4_1 = create(:printer, number: "1", printer_type_id: @pt_4.id)
  end

  describe "model method" do
    context "model and number" do
      it "should return the model and number" do
        expect(@pt_1_1.model_and_number).to eq("#{@pt_1.name}; #{@pt_1_1.name}")
      end
    end

    context "get printer id" do
      it "should return matching ids" do
        expect(Printer.get_printer_ids(@pt_1.name)).to eq(
          [@pt_1_1.id, @pt_1_2.id]
        )
        expect(Printer.get_printer_ids(@pt_2.name)).to eq([@pt_2_1.id])
        expect(Printer.get_printer_ids(@pt_3.name)).to eq(
          [@pt_3_1.id, @pt_3_2.id]
        )
        expect(Printer.get_printer_ids(@pt_4.name)).to eq([@pt_4_1.id])
      end
    end

    context "Get last session" do
      it "should return last session" do
        create :user, :regular_user
        create(:printer_session, printer_id: @pt_1_2.id)
        expect(Printer.get_last_model_session(@pt_1.name).printer.number).to eq(
          @pt_1_2.number
        )
      end
    end

    context "Get last session for printer" do
      it "should return last session of that specific printer" do
        create :user, :regular_user
        create(:printer_session, printer_id: @pt_1_2.id)
        expect(
          Printer.get_last_number_session(@pt_1_2.id).printer.number
        ).to eq(@pt_1_2.number)
      end
    end

    describe "#assign_to!" do
      let(:user) { create(:user, :regular_user) }

      it "opens an in-use session and closes the previous one that was in use" do
        previous = create(:printer_session, printer_id: @pt_1_2.id, in_use: true)
        @pt_1_2.assign_to!(user)
        expect(previous.reload.in_use).to be(false)
        expect(Printer.get_last_number_session(@pt_1_2.id)).to have_attributes(user_id: user.id, in_use: true)
      end

      it "works for a printer with no sessions" do
        expect { @pt_1_2.assign_to!(user) }.to change { @pt_1_2.printer_sessions.count }.from(0).to(1)
      end
    end

    describe "#release!" do
      it "closes the last session and creates none" do
        session = create(:printer_session, printer_id: @pt_1_2.id, in_use: true)
        expect { @pt_1_2.release! }.not_to change(PrinterSession, :count)
        expect(session.reload.in_use).to be(false)
      end

      it "does nothing for a printer with no sessions" do
        expect { @pt_1_2.release! }.not_to change(PrinterSession, :count)
      end
    end
  end
end
