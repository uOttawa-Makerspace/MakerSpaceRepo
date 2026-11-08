# frozen_string_literal: true

require "rails_helper"

# What the on-screen report page computes for each report type (the instance
# variables its partials draw from), for populated, repeated and empty data,
# with and without a date range. Templates are not rendered here; the rendered
# pages are covered in spec/requests/admin_report_generator_request_spec.rb.
RSpec.describe Admin::ReportGeneratorController, type: :controller, skip_bullet: true do
  include ActiveSupport::Testing::TimeHelpers

  let(:march_10) { Time.utc(2026, 3, 10, 15, 0, 0) }
  let(:range) { { start_date: "2026-03-01", end_date: "2026-03-31" } }
  let(:admin) { create(:user, :admin) }
  let!(:alpha) { create(:space, name: "Space One") }

  before do
    session[:user_id] = admin.id
    session[:expires_at] = Time.zone.now + 10_000
  end

  def ivar(name)
    controller.instance_variable_get("@#{name}")
  end

  def report(type, params = {})
    get :index, params: { report_type: type }.merge(params)
    expect(response).to have_http_status(:ok)
  end

  describe "certifications" do
    before do
      course = create(:course_name, name: "MCG1")
      wood = create(:skill, name: "Woodshop")
      tech = create(:skill, name: "Tech")
      laser = create(:training, name_en: "Laser", skill: wood)
      saw = create(:training, name_en: "Saw", skill: tech)
      with_course = create(:training_session, space: alpha, training: laser, course_name: course, created_at: march_10)
      orphan = create(:training_session, space: alpha, training: saw, created_at: march_10)
      orphan.update_columns(space_id: nil)
      2.times { create(:certification, training_session: with_course, training: laser, created_at: march_10) }
      create(:certification, training_session: orphan, training: saw, created_at: march_10)
      create(:certification, training_session: with_course, training: laser, created_at: Time.utc(2026, 6, 1))
    end

    it "counts certificates per space, course, skill and training, with unknown for a missing space or course" do
      report("certifications", range)
      expect(ivar(:certs).count).to eq(3)
      expect(ivar(:space_count)).to eq("unknown" => 1, "Space One" => 2)
      expect(ivar(:course_count)).to eq("unknown" => 1, "MCG1" => 2)
      expect(ivar(:skill_count)).to eq("Woodshop" => 2, "Tech" => 1)
      expect(ivar(:training_count)).to eq("Laser" => 2, "Saw" => 1)
    end

    it "without dates counts every certificate" do
      report("certifications")
      expect(ivar(:certs).count).to eq(4)
      expect(ivar(:training_count)).to eq("Laser" => 3, "Saw" => 1)
    end

    it "uses all time when only one of the two dates is given" do
      report("certifications", start_date: "2026-03-01")
      expect(ivar(:certs).count).to eq(4)
    end

    it "with nothing recorded leaves only the unknown buckets at zero" do
      Certification.delete_all
      report("certifications", range)
      expect(ivar(:space_count)).to eq("unknown" => 0)
      expect(ivar(:course_count)).to eq("unknown" => 0)
      expect(ivar(:skill_count)).to eq({})
    end
  end

  describe "trainings" do
    before do
      laser = create(:training, name_en: "Laser")
      saw = create(:training, name_en: "Saw")
      create(:training_session, space: alpha, training: laser, created_at: march_10).users << create(:user) << create(:user)
      create(:training_session, space: alpha, training: laser, created_at: march_10 + 1.day).users << create(:user)
      lonely = create(:training_session, space: alpha, training: saw, created_at: march_10)
      lonely.update_columns(space_id: nil)
      create(:training_session, space: alpha, training: saw, created_at: Time.utc(2026, 8, 1))
    end

    it "counts sessions per space and training and sums attendees; a session without a space is unknown" do
      report("trainings", range)
      expect(ivar(:space_count)).to eq("unknown" => 1, "Space One" => 2)
      expect(ivar(:trainings_count)).to eq("Laser" => 2, "Saw" => 1)
      expect(ivar(:attendance_count)).to eq("Laser" => 3, "Saw" => 0)
    end

    it "without dates includes the session from August" do
      report("trainings")
      expect(ivar(:trainings_count)).to eq("Laser" => 2, "Saw" => 2)
    end
  end

  describe "new_projects" do
    it "counts how many projects use each category and equipment" do
      one = create(:repository, created_at: march_10)
      two = create(:repository, created_at: march_10)
      create(:repository, created_at: Time.utc(2026, 9, 1))
      [one, two].each do |repo|
        create(:category, repository: repo, name: "Robotics")
        create(:equipment, repository: repo, name: "Printer")
      end
      create(:equipment, repository: one, name: "Laser")
      report("new_projects", range)
      expect(ivar(:repos).count).to eq(2)
      expect(ivar(:category_count)).to eq("Robotics" => 2)
      expect(ivar(:equipment_count)).to eq("Printer" => 2, "Laser" => 1)
      report("new_projects")
      expect(ivar(:repos).count).to eq(3)
    end
  end

  describe "visitors" do
    before do
      beta = create(:space, name: "Space Two")
      eng = create(:user, :student)
      community = create(:user)
      community.update_columns(faculty: "")
      gone = create(:user, :student, program: "Arts", faculty: "Arts")
      create(:lab_session, space: alpha, user: eng, created_at: march_10)
      create(:lab_session, space: alpha, user: eng, created_at: march_10 + 1.hour)
      create(:lab_session, space: beta, user: community, created_at: march_10)
      create(:lab_session, space: beta, user: gone, created_at: march_10)
      gone.soft_delete!
      create(:lab_session, space: beta, user: eng, created_at: march_10).update_columns(user_id: nil)
      create(:lab_session, space: alpha, user: eng, created_at: Time.utc(2026, 9, 1))
    end

    it "tallies visits and unique visitors by space, identity and faculty; a visit with no user is unknown, a deleted user keeps their own identity" do
      report("visitors", range)
      expect(ivar(:space_total_count)).to eq("Space One" => 2, "Space Two" => 3)
      expect(ivar(:space_unique_count)).to eq("Space One" => 1, "Space Two" => 2)
      expect(ivar(:identity_total_count)).to eq("Undergrad" => 3, "Community member" => 1, "Unknown" => 1)
      expect(ivar(:identity_unique_count)).to eq("Undergrad" => 2, "Community member" => 1)
      expect(ivar(:faculty_total_count)).to eq("Engineering" => 2, "" => 1, "Arts" => 1, "unknown" => 1)
      expect(ivar(:faculty_unique_count)).to eq("Engineering" => 1, "" => 1, "Arts" => 1)
    end

    it "without dates counts every visit" do
      report("visitors")
      expect(ivar(:space_total_count)).to eq("Space One" => 3, "Space Two" => 3)
    end
  end

  describe "visits_by_hour" do
    it "returns the all-time relation plus one relation per space keyed by the space name with dashes" do
      create(:space, name: "Space Two")
      create(:lab_session, space: alpha, user: create(:user), created_at: march_10)
      create(:lab_session, space: alpha, user: create(:user), created_at: Time.utc(2026, 9, 1))
      report("visits_by_hour", range)
      hash = ivar(:lab_hash)
      expect(hash.keys).to eq(%w[all Space-One Space-Two])
      expect(hash["all"].count).to eq(1)
      expect(hash["Space-One"].count).to eq(1)
      expect(hash["Space-Two"].count).to eq(0)
      expect(ivar(:spaces).map(&:name)).to eq(["Space One", "Space Two"])
      report("visits_by_hour")
      expect(ivar(:lab_hash)["all"].count).to eq(2)
      expect(ivar(:lab_hash)["Space-One"].count).to eq(2)
    end
  end

  describe "kit_purchased" do
    it "counts purchased kits per project title" do
      blinky = create(:proficient_project, title: "Blinky")
      lamp = create(:proficient_project, title: "Lamp")
      2.times { create(:project_kit, proficient_project: blinky, created_at: march_10) }
      create(:project_kit, proficient_project: lamp, created_at: march_10)
      create(:project_kit, proficient_project: lamp, created_at: Time.utc(2026, 9, 1))
      report("kit_purchased", range)
      expect(ivar(:pp_hash)).to eq("Blinky" => 2, "Lamp" => 1)
      report("kit_purchased")
      expect(ivar(:pp_hash)).to eq("Blinky" => 2, "Lamp" => 2)
    end
  end

  describe "training_attendees" do
    before do
      session = create(:training_session, space: alpha, created_at: march_10)
      other = create(:training_session, space: alpha, created_at: march_10)
      3.times { create(:certification, training_session: session, created_at: march_10) }
      create(:certification, training_session: other, created_at: march_10)
    end

    it "averages certificates per session for each month that has some, as a float" do
      report("training_attendees", range)
      expect(ivar(:monthly_average)).to eq("March" => 2.0)
      expect(ivar(:spaces).map(&:name)).to eq(["Space One"])
    end

    it "a range that does not include the 1st of the month sees no months" do
      report("training_attendees", start_date: "2026-03-05", end_date: "2026-03-20")
      expect(ivar(:monthly_average)).to eq({})
    end

    it "without dates walks every month since June 2015 up to now and folds the same month of every year together" do
      travel_to(Time.utc(2026, 11, 6, 12)) do
        create(:certification, training_session: create(:training_session, space: alpha, created_at: Time.utc(2025, 3, 3)),
                               created_at: Time.utc(2025, 3, 3))
        report("training_attendees")
        # March 2025 (1 cert, 1 session) and March 2026 (4 certs, 2 sessions) give 5 certs over 3 sessions
        expect(ivar(:monthly_average)).to eq("March" => 5.0 / 3)
      end
    end
  end

  describe "popular_hours" do
    it "without dates picks the signed-in admin's last visited space, else the first space" do
      report("popular_hours")
      expect(ivar(:space)).to eq(Space.first)
      beta = create(:space, name: "Space Two")
      create(:lab_session, space: beta, user: admin, created_at: march_10)
      report("popular_hours")
      expect(ivar(:space)).to eq(beta)
      expect(ivar(:spaces).map(&:name)).to eq(["Space One", "Space Two"])
      expect(ivar(:weekdays)).to eq(Date::DAYNAMES)
      expect(ivar(:info)).to be_nil
    end

    it "with dates builds the per-weekday hourly averages and renames the report type" do
      create(:lab_session, space: alpha, user: create(:user), created_at: Time.utc(2026, 3, 10, 15))
      create(:lab_session, space: alpha, user: create(:user), created_at: Time.utc(2026, 3, 10, 15, 30))
      report("popular_hours", start_date: "2026-03-01", end_date: "2026-03-14")
      info = ivar(:info)
      expect(info.keys).to eq([alpha.id])
      # 2026-03-10 is a Tuesday (wday 2); two Tuesdays in the 14 days -> 2 visits / 2 days
      expect(info[alpha.id][2][15]).to eq(1.0)
      expect(info[alpha.id][2][14]).to eq(0.0)
      expect(controller.params[:report_type]).to eq("popular_hours_per_period")
    end
  end

  describe "frequent_visitors" do
    before do
      @regular = create(:user, name: "Reg Ular")
      @weekender = create(:user, name: "Wee Kender")
      create(:lab_session, space: alpha, user: @regular, created_at: Time.utc(2026, 3, 3, 12))
      create(:lab_session, space: alpha, user: @regular, created_at: Time.utc(2026, 3, 4, 12))
      create(:lab_session, space: alpha, user: @weekender, created_at: Time.utc(2026, 3, 7, 12))
    end

    it "lists the top visitors per space for the whole range and for weekends only" do
      report("frequent_visitors", start_date: "2026-03-01", end_date: "2026-03-08")
      expect(ivar(:weekends).size).to eq(3) # Sun 1st, Sat 7th, Sun 8th
      name, all_days, weekends = ivar(:lab_sessions).first
      expect(name).to eq("Space One")
      expect(all_days).to eq(@regular => 2, @weekender => 1)
      expect(weekends).to eq(@weekender => 1)
    end

    it "gives empty tables for a space nobody visited" do
      create(:space, name: "Space Two")
      report("frequent_visitors", start_date: "2026-03-01", end_date: "2026-03-08")
      expect(ivar(:lab_sessions).last).to eq(["Space Two", {}, {}])
    end
  end

  describe "new_users" do
    it "uses the dated, soft-delete-inclusive relation with dates and all users without" do
      create(:user, created_at: march_10)
      create(:user, created_at: march_10).soft_delete!
      create(:user, created_at: Time.utc(2020, 1, 1))
      report("new_users", range)
      expect(ivar(:users).count).to eq(2)
      report("new_users")
      expect(ivar(:users).count).to be >= 4
    end
  end

  describe "unknown report type" do
    it "answers 400 even when dates are given" do
      get :index, params: { report_type: "bogus" }.merge(range)
      expect(response).to have_http_status(:bad_request)
      expect(response.body).to eq("Unknown report type")
    end
  end
end
