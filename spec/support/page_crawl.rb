# frozen_string_literal: true

# Shared machinery for the role-based page crawl
# (spec/requests/page_crawl_spec.rb and spec/system/page_crawl_spec.rb).
#
# Enumerates every GET route of the app (minus engines, assets, ActiveStorage,
# MissionControl, webhooks and a short list of mutating/external GETs), fills
# :id / :username style params from a seeded "world" (one record per main
# model) and records which routes it could not fill.
module PageCrawl
  Route = Struct.new(:path_spec, :controller, :action, :name, keyword_init: true) do
    def key = "#{controller}##{action}"
    def label = path_spec
  end

  PASSWORD = "asa32A353#"
  ROLES = %i[guest regular staff admin].freeze

  # GET routes that mutate state, sign out, hit an external provider or render
  # a heavy report; visiting them would change the shared world or the session.
  SKIP_ROUTES = [
    [%r{\A/logout\z}, "destroys the session"],
    [%r{\A/staff_dashboard/sign_out_all_users\z}, "mutates: signs everyone out"],
    [%r{\A/cc_moneys/redeem\z}, "mutates: credits CC (D-B... redeem is a GET)"],
    [%r{\A/cc_moneys/link_cc_to_user\z}, "mutates: links CC to a user"],
    [%r{/join_}, "mutates: joins a program/proposal"],
    [%r{/unjoin_}, "mutates: leaves a proposal"],
    [%r{\A/project_proposals/(un)?join_project_proposal\z}, "mutates"],
    [%r{\A/proficient_projects/(approve|revoke)_project\z}, "mutates: approves/revokes"],
    [%r{\A/proficient_projects/generate_acquired_badge\z}, "mutates: issues a badge"],
    [%r{\A/project_kits/:project_kit_id/mark_delivered\z}, "mutates"],
    [%r{\A/order_items/:order_item_id/revoke\z}, "mutates: revokes an order item (GET alias of destroy)"],
    [%r{\A/remove_avatar\z}, "mutates: removes the avatar"],
    [%r{\A/unlock_account\z}, "mutates: unlocks an account (token)"],
    [%r{\A/confirm\z}, "needs a signed token"],
    [%r{\A/confirm_edited_email\z}, "needs a signed token"],
    [%r{\A/resend_confirmation\z}, "sends mail, mutates"],
    [%r{\A/resend_email_confirmation\z}, "sends mail"],
    [%r{\A/saml/}, "SAML IdP, needs a SAML request"],
    [%r{\A/admin/cdel_reports/generate_output\z}, "heavy report generation"],
    [%r{\A/admin/report_generator/generate_spreadsheet\z}, "heavy spreadsheet generation"],
    [%r{\A/job_orders/(pay|user_magic_approval)\z}, "needs a signed token"],
    [%r{\A/videos/:id/download/:filename\z}, "streams a stored file"],
    [%r{/download_files\z}, "streams a zip"],
    [%r{\A/learning_area/:id/scorm_launch\z}, "SCORM package launch"],
    [%r{\A/admin/calendar/ics_to_json\z}, "fetches an external ICS feed"],
    [%r{\A/open_hours\z}, "fetches external ICS calendars"],
    [%r{\A/rfid/get_unset_rfids\z}, "consumes RFID reader state"],
    [%r{\A/kiosk}, "kiosk screens (device-bound)"]
  ].freeze

  # Segments that are not routable params in this crawl.
  IGNORED_PATH = [%r{\A/(rails|cable|mission_control|assets|vite|packs|cdn-cgi)(/|\z)}, %r{active_storage}, %r{webhook}].freeze

  module_function

  def routes
    Rails.application.routes.routes.filter_map do |r|
      next unless r.verb.to_s.include?("GET")
      next if r.defaults[:controller].blank?

      app = r.app.respond_to?(:app) ? r.app.app : r.app
      next if app.is_a?(Class) && app < Rails::Engine

      path = r.path.spec.to_s.sub("(.:format)", "")
      next if IGNORED_PATH.any? { |re| path.match?(re) }

      Route.new(path_spec: path, controller: r.defaults[:controller], action: r.defaults[:action], name: r.name)
    end.uniq(&:path_spec)
  end

  def skip_reason(route)
    SKIP_ROUTES.each { |re, why| return why if route.path_spec.match?(re) }
    nil
  end

  # Substitutes :params from the world. Returns [path, nil] or [nil, reason].
  def fill(route, world)
    missing = nil
    path = route.path_spec.gsub(/:(\w+)/) do
      value = world.value_for(route.controller, Regexp.last_match(1))
      if value.nil?
        missing ||= Regexp.last_match(1)
        next ":#{Regexp.last_match(1)}"
      end
      value.to_s
    end
    missing ? [nil, "no world record for :#{missing} (#{route.controller})"] : [path, nil]
  end

  # One record per main model. Everything is built inside the example (rolled
  # back with it). Builders that fail leave their key nil so the matching
  # routes are skipped and reported instead of breaking the crawl.
  class World
    include FactoryBot::Syntax::Methods
    attr_reader :records, :failures

    # controller basename -> world key, where singularize is not enough
    CONTROLLER_KEYS = {
      "learning_area" => :learning_module,
      "unavailabilities" => :staff_unavailability,
      "my_calendar" => :staff_needed_calendar,
      "calendar" => :staff_needed_calendar,
      "sub_space_booking" => :sub_space_booking,
      "kiosk" => :user,
      "key_requests" => :key_request,
      "badges" => :certification,
      "faqs" => :faq,
      "design_days" => :design_day,
      "staff_spaces" => :staff_space,
      "staff_availabilities" => :staff_availability,
      "walk_in_safety_sheets" => :walk_in_safety_sheet,
      "users" => :user,
      "uni_programs" => :uni_program
    }.freeze

    PARAM_KEYS = {
      "username" => :target_username,
      "user_username" => :target_username,
      "slug" => :slug,
      "shortcut" => :shortcut,
      "subskill" => :subskill,
      "filename" => :filename,
      "file_number" => :file_number,
      "repository_id" => :repository,
      "training_session_id" => :training_session,
      "job_order_id" => :job_order,
      "sub_space_booking_id" => :sub_space_booking,
      "key_id" => :key,
      "locker_id" => :locker,
      "order_item_id" => :order_item,
      "proficient_project_id" => :proficient_project,
      "project_kit_id" => :project_kit,
      "key_request_id" => :key_request
    }.freeze

    # ctx: the running example group (gives access to the job-order seed helpers)
    def initialize(ctx)
      @ctx = ctx
      @records = {}
      @failures = {}
      build
    end

    def value_for(controller, param)
      if param == "id"
        base = controller.split("/").last
        key = CONTROLLER_KEYS[base] || base.singularize.to_sym
        # nested resources whose :id is the child (job_tasks)
        key = :job_task if base == "job_tasks"
        key = :order_item if base == "order_items"
        key = :repository if %w[repositories makes].include?(base)
        return records[key]&.then { |r| r.respond_to?(:id) ? r.id : r }
      end
      key = PARAM_KEYS[param] || param.sub(/_id\z/, "").to_sym
      v = records[key]
      v.respond_to?(:id) ? v.id : v
    end

    private

    def make(key)
      records[key] = yield
    rescue StandardError, NotImplementedError => e
      @failures[key] = "#{e.class}: #{e.message.lines.first&.strip}"
      records[key] = nil
    end

    def build
      make(:target) { create(:user, :regular_user) }
      records[:user] = records[:target]
      records[:target_username] = records[:target]&.username
      make(:space) { create(:space) }
      make(:sub_space) { create(:sub_space, space: records[:space]) }
      make(:training) { create(:training) }
      make(:training_session) { create(:training_session, user: create(:user, :staff), training: records[:training]) }
      make(:question) { create(:question).tap { |q| records[:training].questions << q } }
      make(:exam) { create(:exam, user: records[:target], training_session: records[:training_session]) }
      make(:skill) { create(:skill) }
      make(:certification) { create(:certification, :basic_training, user_id: records[:target].id) }
      make(:repository) { create(:repository, owner: records[:target]) }
      make(:proficient_project) { create(:proficient_project, training: records[:training]) }
      make(:project_kit) { create(:project_kit, proficient_project: records[:proficient_project]) }
      make(:learning_module) { create(:learning_module, training: records[:training]) }
      make(:faq) { create(:faq) }
      make(:announcement) { create(:announcement) }
      make(:project_proposal) { create(:project_proposal) }
      make(:printer_type) { create(:printer_type, :Random) }
      make(:printer) { create(:printer, :Random) }
      make(:printer_issue) { create(:printer_issue, printer: records[:printer], reporter: records[:target]) }
      make(:locker) { create(:locker) }
      make(:locker_rental) { create(:locker_rental, :active, rented_by: records[:target], locker: records[:locker]) }
      make(:volunteer_task) { create(:volunteer_task, space: records[:space]) }
      make(:volunteer_hour) { create(:volunteer_hour, user: records[:target]) }
      make(:key) { create(:key, space: records[:space]) }
      make(:key_request) do
        create(:key_request, :status_waiting_for_approval, :all_questions_answered, user: records[:target],
                                                                   space: records[:space], supervisor: create(:user, :admin))
      end
      make(:key_certification) { create(:key_certification, user: records[:target]) }
      make(:key_transaction) { create(:key_transaction, user: records[:target], key: records[:key]) }
      make(:order) { create(:order, user: records[:target]) }
      make(:order_item) { create(:order_item, order: records[:order], proficient_project: records[:proficient_project]) }
      make(:event) { create(:event, space: records[:space]) }
      make(:staff_needed_calendar) { create(:staff_needed_calendar, space: records[:space], calendar_url: "https://calendar.example.test/x.ics", role: "open_hours") }
      make(:staff_unavailability) { create(:staff_unavailability) }
      make(:staff_availability) { create(:staff_availability) }
      make(:contact_info) { create(:contact_info) }
      make(:drop_off_location) { create(:drop_off_location) }
      make(:time_period) { create(:time_period) }
      make(:coupon_code) { create(:coupon_code) }
      make(:video) { create(:video) }
      make(:design_day) { create(:design_day) }
      make(:uni_program) { create(:uni_program) }
      # UniProgram.no_program (signup form) needs the faculty-less row
      make(:no_program) { UniProgram.unscoped.find_by(faculty: "") || create(:uni_program, faculty: "", program: "No program") }
      make(:walk_in_safety_sheet) do
        create(:walk_in_safety_sheet, :is_adult, user: records[:target], space: records[:space],
                                                participant_signature: "Sig", participant_telephone_at_home: "613-555-0100")
      end
      make(:team) do
        Team.create!(name: "Crawl Team").tap { |t| TeamMembership.create!(team: t, user: records[:target], role: :captain) }
      end
      make(:job_service_group) { create(:job_service_group) }
      make(:job_service) { create(:job_service, job_service_group: records[:job_service_group]) }
      make(:job_option) { create(:job_option) }
      make(:job_type) { JobType.find_by(name: "3D Print") || create(:job_type) }
      make(:staff_space) { create(:staff_space, space: records[:space]) }
      make(:locker_size) { records[:locker]&.locker_size }
      make(:job_order) { seed_job_order_world }
      make(:job_task) { records[:job_order]&.job_tasks&.first }
      make(:sub_space_booking) { seed_booking_world }
      records[:slug] = "crawl-slug"
      records[:shortcut] = "crawl"
      records[:subskill] = "crawl"
      records[:filename] = "x.txt"
      records[:file_number] = "1"
    end

    def seed_job_order_world
      @ctx.seed_job_statuses!
      @ctx.seed_job_order_message!
      @ctx.seed_job_types!
      order = @ctx.make_job_order!(owner: records[:target], status_key: :staff_approval)
      order.job_tasks.create!(title: "Task #1", job_type: JobType.find_by!(name: "3D Print"))
      order
    end

    def seed_booking_world
      ids = %w[Pending Approved Rejected].map { |n| BookingStatus.find_by(name: n) || BookingStatus.create!(name: n) }
      records[:booking_statuses] = ids
      create(:sub_space_booking, sub_space: records[:sub_space], user: records[:target]).tap do |b|
        b.sub_space_booking_status.update!(booking_status_id: ids.first.id)
      end
    end
  end
end
