# frozen_string_literal: true

require "rails_helper"

# The popular hours and training attendees reports list every space. What they read per space and weekday must not
# cost queries that grow with the number of spaces.
RSpec.describe "Admin report generator per-space queries", type: :request do
  include Chunk18Helpers

  let(:march_10) { Time.utc(2026, 3, 10, 15, 0, 0) }
  let(:range) { { start_date: "2026-03-01", end_date: "2026-03-31" } }

  before { c18_sign_in(:admin) }

  def add_space_with_popular_hours
    space = create(:space)
    [1, 3, 5].each do |day|
      [9, 10].each { |hour| create(:popular_hour, space: space, day: day, hour: hour, mean: day + (hour / 10.0)) }
    end
    space
  end

  def add_space_with_attendee
    space = create(:space)
    training = create(:training)
    session = create(:training_session, space: space, training: training, created_at: march_10)
    create(:certification, user: create(:user, :student), training_session: session, training: training, space: space,
                           created_at: march_10)
    space
  end

  describe "popular hours" do
    def popular_hours_queries
      count_queries { get admin_report_generator_index_path, params: { report_type: "popular_hours" } }
    end

    it "draws a chart per weekday with rows, with the hours in order" do
      space = create(:space, name: "Chart Space")
      create(:popular_hour, space: space, day: 2, hour: 11, mean: 4.0)
      create(:popular_hour, space: space, day: 2, hour: 9, mean: 2.0)
      create(:popular_hour, space: space, day: 2, hour: 10, mean: 3.0)

      get admin_report_generator_index_path, params: { report_type: "popular_hours" }

      expect(response.body).to include("data: [2.0, 3.0, 4.0]")
      expect(response.body).to include('id="Chart-Space-2"')
      expect(response.body).not_to include('id="Chart-Space-1"')
    end

    it "runs the same number of queries for more spaces" do
      2.times { add_space_with_popular_hours }
      popular_hours_queries # the first request also warms caches
      few = popular_hours_queries
      2.times { add_space_with_popular_hours }
      many = popular_hours_queries

      expect(many).to eq(few)
    end
  end

  describe "training attendees" do
    def attendees_queries
      count_queries { get admin_report_generator_index_path, params: range.merge(report_type: "training_attendees") }
    end

    it "lists each space's attendees by training session, oldest first, and leaves out spaces with none" do
      space = create(:space, name: "Busy Space")
      create(:space, name: "Quiet Space")
      training = create(:training, name_en: "Welding")
      older = create(:training_session, space: space, training: training, created_at: march_10)
      newer = create(:training_session, space: space, training: training, created_at: march_10)
      older.update_columns(updated_at: march_10)
      newer.update_columns(updated_at: march_10 + 1.day)
      first = create(:user, :student, name: "First Attendee")
      second = create(:user, :student, name: "Second Attendee")
      create(:certification, user: first, training_session: older, training: training, space: space, created_at: march_10)
      create(:certification, user: second, training_session: newer, training: training, space: space, created_at: march_10)

      get admin_report_generator_index_path, params: range.merge(report_type: "training_attendees")

      expect(response.body).to include("Busy Space - 2 attendees")
      expect(response.body).not_to include("Quiet Space -")
      expect(response.body.index("First Attendee")).to be < response.body.index("Second Attendee")
    end

    it "runs the same number of queries for more spaces" do
      2.times { add_space_with_attendee }
      attendees_queries # the first request also warms caches
      few = attendees_queries
      2.times { add_space_with_attendee }
      many = attendees_queries

      expect(many).to eq(few)
    end
  end
end
