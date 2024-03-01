require "rails_helper"

RSpec.describe Printer, type: :model do
  before(:all) do
    @pt_1 = create(:printer_type, :Random)
    @pt_2 = create(:printer_type, :Random)
    @pt_3 = create(:printer_type, :Random)
    @pt_4 = create(:printer_type, :Random)

    @pt_1_1 =
      create(
        :printer,
        number: "#{@pt_1.short_form} - 1",
        printer_type_id: @pt_1.id
      )
    @pt_1_2 =
      create(
        :printer,
        number: "#{@pt_1.short_form} - 2",
        printer_type_id: @pt_1.id
      )
    @pt_2_1 =
      create(
        :printer,
        number: "#{@pt_2.short_form} - 1",
        printer_type_id: @pt_2.id
      )
    @pt_3_1 =
      create(
        :printer,
        number: "#{@pt_3.short_form} - 1",
        printer_type_id: @pt_3.id
      )
    @pt_3_2 =
      create(
        :printer,
        number: "#{@pt_3.short_form} - 2",
        printer_type_id: @pt_3.id
      )
    @pt_4_1 =
      create(
        :printer,
        number: "#{@pt_4.short_form} - 1",
        printer_type_id: @pt_4.id
      )
  end

  describe "model method" do
    context "model and number" do
      it "should return the model and number" do
        expect(@pt_1_1.model_and_number).to eq(
          "#{@pt_1.name}; Number #{@pt_1_1.number}"
        )
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
  end
end
