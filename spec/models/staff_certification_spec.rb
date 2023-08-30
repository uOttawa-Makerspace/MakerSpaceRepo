require "rails_helper"

RSpec.describe StaffCertification, type: :model do
  describe "Associations" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
    end
  end

  describe "Validations" do
    before :all do
      @user = create(:user, :staff)
    end

    context "user validations" do
      it "should be valid since user is present" do
        sc = build(:staff_certification, user_id: @user.id)
        expect(sc.valid?).to be_truthy
      end

      it "should be invalid since user is not present" do
        sc = build(:staff_certification)
        expect(sc.valid?).to be_falsey
      end
    end

    context "file validations" do
      it "should be valid since all files are pdf files" do
        sc = build(:staff_certification, user_id: @user.id)
        (1..StaffCertification::TOTAL_NUMBER_OF_FILES).each do |i|
          pdf_file =
            fixture_file_upload(
              Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
              "application/pdf"
            )
          sc.send("pdf_file_#{i}").attach(pdf_file)
        end
        expect(sc.valid?).to be_truthy
      end

      it "should be invalid since one file is not a pdf" do
        sc = build(:staff_certification, user_id: @user.id)
        png_file =
          fixture_file_upload(
            Rails.root.join("spec/support/assets", "avatar.png"),
            "image/png"
          )
        sc.send("pdf_file_1").attach(png_file)
        expect(sc.valid?).to be_falsey
      end
    end
  end

  describe "Methods" do
    before :all do
      @user = create(:user, :staff, name: "John Doe")
      @staff_cert = create(:staff_certification, user_id: @user.id)
    end

    context "#generate_filename" do
      it "should return the right filename" do
        expect(@staff_cert.generate_filename(1)).to eq("john-doe-WHMIS.pdf")
      end
    end

    context "#attach_pdf_file" do
      it "should attach the file" do
        pdf_file =
          fixture_file_upload(
            Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
            "application/pdf"
          )
        @staff_cert.attach_pdf_file(1, pdf_file)

        expect(@staff_cert.send("pdf_file_1").blob.filename).to eq(
          "john-doe-WHMIS.pdf"
        )
      end
    end

    context "#get_staff_certs_attached" do
      it "should get the number of staff certifications attached" do
        pdf_file =
          fixture_file_upload(
            Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
            "application/pdf"
          )
        (1..3).each { |i| @staff_cert.send("pdf_file_#{i}").attach(pdf_file) }
        expect(@staff_cert.get_staff_certs_attached).to eq(3)
      end
    end

    context "#get_supervisor_certs_attached" do
      it "should return 0" do
        pdf_file =
          fixture_file_upload(
            Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
            "application/pdf"
          )
        (1..3).each { |i| @staff_cert.send("pdf_file_#{i}").attach(pdf_file) }
        expect(@staff_cert.get_supervisor_certs_attached).to eq(0)
      end

      it "should return 1" do
        pdf_file =
          fixture_file_upload(
            Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
            "application/pdf"
          )
        @staff_cert.send(
          "pdf_file_#{StaffCertification::NUMBER_OF_STAFF_FILES + 1}"
        ).attach(pdf_file)
        expect(@staff_cert.get_supervisor_certs_attached).to eq(1)
      end
    end
  end
end
