# frozen_string_literal: true

require "rails_helper"

# The profile skills tab, the volunteer stats, proficient projects, learning area and development
# programs skills pages show each training's standing, badge and recommended hours for the signed-in
# user. The rendered output is pinned for trainings in every state, and the queries on the progress
# tables must not grow with the number of trainings listed.
RSpec.describe "Training standing, badge and recommended hours on the skills pages", type: :request do
  include ContentSpecHelpers

  HELPER_TABLES = /FROM "(certifications|training_sessions|proficient_projects|learning_modules|order_items)"/

  let(:user) { create(:user, :volunteer_with_volunteer_program) }
  let(:skill) { create(:skill) }

  # name => the user's progress: nothing, a started project, a started module, or a certification level
  STATES = {
    "Idle" => nil,
    "Projecty" => :project,
    "Moduley" => :module,
    "Starter" => "Beginner",
    "Middler" => "Intermediate",
    "Master" => "Advanced"
  }.freeze

  def add_training(name, state)
    training = create(:training, skill: skill, name_en: name, name_fr: "#{name} fr")
    create(:proficient_project, training: training, level: "Beginner", title: "#{name} pb")
    advanced = create(:proficient_project, training: training, level: "Advanced", title: "#{name} pa")
    done = create(:learning_module, training: training, level: "Beginner", title: "#{name} mb")
    create(:learning_module, training: training, level: "Intermediate", title: "#{name} mi")
    Array(state).each { |progress| add_progress(training, progress, advanced, done) }
    training
  end

  def add_progress(training, state, project, learning_module)
    case state
    when :project
      create(:order_item, :awarded, proficient_project: project, order: create(:order, :completed, user: user))
    when :module
      create(:learning_module_track, :completed, user: user, learning_module: learning_module)
    when String
      session = create(:training_session, training: training, level: state)
      create(:certification, user: user, training: training, training_session: session, level: state)
    end
  end

  def counted?(payload)
    payload[:sql].match?(HELPER_TABLES) && payload[:name] != "SCHEMA"
  end

  def sql_during
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if counted?(payload) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  def page_text
    Nokogiri::HTML(response.body).text.squish
  end

  STATUS = /(?:🐣 Not Started|🐥 Newbie|🦆 Beginner|🦩 Intermediate|🦅 Advanced)/

  NOT_STARTED = "🐣 Not Started"
  NEWBIE = "🐥 Newbie"
  BEGINNER = "🦆 Beginner"
  INTERMEDIATE = "🦩 Intermediate"
  ADVANCED = "🦅 Advanced"

  PAGES = {
    "the profile skills tab" => -> { user_path(user.username) },
    "the volunteer stats page" => -> { my_stats_volunteers_path },
    "the proficient projects page" => -> { proficient_projects_path },
    "the learning area page" => -> { learning_area_index_path },
    "the development programs skills page" => -> { skills_development_programs_path }
  }.freeze

  PAGES.each do |label, path|
    describe label do
      before { content_login!(user) }

      it "queries the progress tables the same number of times for four trainings or ten" do
        add_training("First", :project)
        add_training("Second", :module)
        add_training("Third", "Intermediate")
        add_training("Fourth", "Advanced")
        get instance_exec(&path)
        few = sql_during { get instance_exec(&path) }
        STATES.each { |name, state| add_training("More #{name}", state) }
        many = sql_during { get instance_exec(&path) }

        expect(many.size).to eq(few.size)
      end
    end
  end

  STANDINGS = {
    "Idle" => NOT_STARTED, "Projecty" => NEWBIE, "Moduley" => NEWBIE,
    "Starter" => BEGINNER, "Middler" => INTERMEDIATE, "Master" => ADVANCED
  }.freeze

  describe "rendered output for trainings in every state" do
    before do
      content_login!(user)
      STATES.each { |name, state| add_training(name, state) }
    end

    # The page text from each training's name and standing up to the next training's.
    def cards
      names = STANDINGS.keys.join("|")
      page_text.split(/(?=\b(?:#{names}) #{STATUS})/).grep(/\A(?:#{names}) #{STATUS}/).to_h { |card| [card[/\A\w+/], card] }
    end

    def standings = cards.transform_values { |card| card[STATUS] }

    def figures(pattern) = cards.transform_values { |card| card.scan(pattern) }

    it "shows each training's standing, project and module counts and recommended hours on the profile skills tab" do
      get user_path(user.username)

      expect(standings).to eq(STANDINGS)
      expect(figures(/awarded: (\d+) Learning modules completed: (\d+) Recommended hours before moving on: (\d+)/)).to eq(
        "Idle" => [%w[0 0 2]], "Projecty" => [%w[1 0 2]], "Moduley" => [%w[0 1 2]],
        "Starter" => [%w[0 0 2]], "Middler" => [%w[0 0 3]], "Master" => [%w[0 0 4]]
      )
      expect(page_text).to include("Starter I", "Middler II", "Master III")
    end

    it "shows each training's standing and next-level progress on the volunteer stats page" do
      get my_stats_volunteers_path

      expect(standings).to eq(STANDINGS)
      expect(figures(/Next: (\w+) Milestone (.*?) Practice for \w+: (\d+) hrs?/).transform_values { |rows| rows.map { |level, detail, hours| [level, detail.strip, hours] } }).to eq(
        "Idle" => [["Beginner", "Proficient Projects 0 / 1 Learning Modules 0 / 1", "2"]],
        "Projecty" => [["Beginner", "Proficient Projects 0 / 1 Learning Modules 0 / 1", "2"]],
        "Moduley" => [["Beginner", "Proficient Projects 0 / 1 Learning Modules 1 / 1", "2"]],
        "Starter" => [["Intermediate", "Learning Modules 0 / 1", "1"]],
        "Middler" => [["Advanced", "Proficient Projects 0 / 1", "1"]], "Master" => []
      )
      expect(page_text).to include("Mastered")
    end

    it "shows each training's standing and finished projects on the proficient projects page" do
      get proficient_projects_path

      expect(standings).to eq(STANDINGS)
      expect(figures(/finished : (\d+) \/ (\d+)/)).to eq(
        STANDINGS.keys.index_with { |name| [name == "Projecty" ? %w[1 2] : %w[0 2]] }
      )
    end

    it "shows each training's standing on the learning area page, in training name order" do
      get learning_area_index_path

      expect(page_text.scan(STATUS)).to eq([NOT_STARTED, ADVANCED, INTERMEDIATE, NEWBIE, NEWBIE, BEGINNER])
    end

    it "shows each training's standing, counts and recommended hours on the development programs skills page" do
      get skills_development_programs_path

      expect(standings).to eq(STANDINGS)
      expect(figures(/finished : (\d+) \/ (\d+) Learning Modules finished : (\d+) \/ (\d+) Recomended hours before moving on: (\d+)/)).to eq(
        "Idle" => [%w[0 2 0 2 2]], "Projecty" => [%w[1 2 0 2 2]], "Moduley" => [%w[0 2 1 2 2]],
        "Starter" => [%w[0 2 0 2 2]], "Middler" => [%w[0 2 0 2 3]], "Master" => [%w[0 2 0 2 4]]
      )
      expect(page_text).to include("Starter I", "Middler II", "Master III")
    end
  end
end
