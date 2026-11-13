# frozen_string_literal: true

require "rails_helper"

# Staff see the faculty uOEng states on a profile, and the rest of the uOEng record beside the
# user's own fields.
RSpec.describe "uOEng record on the profile", type: :request do
  let(:staff) { create(:user, :staff) }
  let(:student) { create(:user, :regular_user, identity: "undergrad", faculty: "Arts", program: "History", year_of_study: 2, student_id: "300000001") }

  def log_in_via_form!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
  end

  # The value shown next to a label in the profile's about tab.
  def shown(label)
    Nokogiri::HTML(response.body).at_xpath("//span[normalize-space()='#{label}']/following-sibling::span[1]").text.strip
  end

  before { log_in_via_form!(staff) }

  it "shows the faculty the user entered, and no uOEng record, when there is none" do
    get user_path(student.username)

    expect(shown("Faculty")).to eq("Arts")
    expect(response.body).not_to include('data-test="uoeng-record"')
  end

  context "with a uOEng record" do
    before do
      UoengProfile.create!(user: student, emplid: "300000001", faculty_code: "GENIE", faculty: "Engineering", program_code: "CEG",
                           level: "grad", full_time: true, current_semester: true, source: "student_number",
                           checked_at: Time.zone.local(2026, 11, 13, 10))
    end

    it "shows the verified faculty and the record, and keeps the user's own program" do
      get user_path(student.username)

      record = Nokogiri::HTML(response.body).at_css('[data-test="uoeng-record"]').text.squish
      expect(record).to include("CEG", "Graduate", "Full time", "Enrolled this semester", "November 13, 2026")
      expect([shown("Faculty"), shown("Program")]).to eq(%w[Engineering History])
      expect(student.reload.faculty).to eq("Arts")
    end

    it "is not shown to a viewer who is not staff" do
      reset!
      log_in_via_form!(create(:user, :regular_user))

      get user_path(student.username)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-test="uoeng-record"', "CEG", "uOttawa record")
      expect(Nokogiri::HTML(response.body).at_xpath("//span[normalize-space()='Faculty']")).to be_nil
    end

    it "falls back to the user's faculty when the uOEng faculty is not one the app knows" do
      student.uoeng_profile.update!(faculty_code: "ARTS", faculty: nil)

      get user_path(student.username)

      expect(shown("Faculty")).to eq("Arts")
    end
  end
end
