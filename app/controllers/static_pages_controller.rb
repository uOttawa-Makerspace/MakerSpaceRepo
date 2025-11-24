# frozen_string_literal: true

class StaticPagesController < SessionsController
  before_action :current_user, except: [:reset_password]
  before_action :no_container, except: :about

  def home
    @volunteer_program_shadowing_scheduled =
      current_user.shadowing_hours.map do |hours|
        end_time = hours.end_time.strftime '%H:%M'
        formatted_time =
          "#{I18n.l hours.start_time, format: '%A %H:%M'} - #{end_time}"
        [hours.space.name, formatted_time]
      end

    # NOTE: This crashed before, while using get_volunteer_tasks_from_volunteer_joins so
    # It shouldn't happen again, but I added an exception handler just in case.
    @volunteer_program_your_tasks =
      begin
        current_user
          .volunteer_task_joins
          .active
          .order(updated_at: :desc)
          .joins(:volunteer_task)
          .includes(volunteer_task: :space)
          .where(volunteer_task: { status: 'open' })
          .map do |task|
            task_name = task.volunteer_task.title
            space_name = task.volunteer_task.space.name
            formatted_time = task.created_at.strftime '%H:%M'
            [task_name, space_name, formatted_time, task.volunteer_task_id]
          end.take 5 # five most recent
      rescue StandardError
        []
      end

    @recent_projects =
      Rails.cache.fetch 'StaticPagesRecentRepos', expires_in: 5.minutes do
        # This is how you preload active storage attachments, I think
        Repository
          .public_repos
          .order(created_at: :desc)
          .includes(
            photos: {
              image_attachment: [blob: { variant_records: :blob }]
            }
          )
          .limit(15)
      end

    @user_skills =
      Certification
        .where(user: current_user)
        .includes(training_session: :training)
        .limit(5)
        .pluck('trainings.name_en', 'training_sessions.level')

    # Get total tracks in all learning modules
    total_tracks =
      LearningModule
        .all
        .includes(:training)
        .map { |x| x.training.name_en }
        .tally
    # get the total number of tracks completed
    # and in progress under the user's name
    @user_tracks =
      current_user
        .learning_module_tracks
        .group_by { |x| x.learning_module.training.name_en }
        .transform_values { |x| x.map(&:status).tally }
        .map do |key, value|
          [key, "#{value['Completed']}/#{total_tracks[key]}"]
        end

    @contact_info = ContactInfo.where(show_hours: true).order(name: :asc)

    @workshops =
      Rails.cache.fetch 'SimpliEventsRecentEvents', expires_in: 5.minutes do
        workshops =
          Net::HTTP.get_response(
            URI(
              'https://simpli.events/api/organizer/44d09ce5-5999-4bd9-82eb-8a9772963223'
            )
          )
        JSON.parse(workshops.body)['events']
          .select { |x| x['startTime'] >= DateTime.now.to_i * 1000 }
          .sort { |x| -x['startTime'] }
          .take(5)
      rescue StandardError => e
        Rails.logger.error e
        [] # eh
      end

    @makerstore_links =
      Rails.cache.fetch 'ShopifyMakerstoreLinks', expires_in: 5.minutes do
        home_makerstore_links
      end
  end

  def about
  end

  def contact
    @contact_info = ContactInfo.all.order(name: :asc)
  end

  def terms_of_service
  end

  def hours
    @contact_info = ContactInfo.where(show_hours: true).order(name: :asc)

    respond_to do |format|
      format.html { render :hours }
      format.json do
        render json:
                 @contact_info.as_json(
                   include: :opening_hour,
                   only: %i[
                     name
                     email
                     address
                     phone_number
                     show_hours
                     opening_hour
                   ]
                 )
      end
    end
  end

  def open_hours
    calendars = StaffNeededCalendar.where(role: "open_hours")
    
    all_calendars = calendars.flat_map do |calendar_record|
      helpers.parse_ics_calendar(
        calendar_record.calendar_url,
        name: calendar_record.name.presence || calendar_record.space&.name || "Unnamed Calendar",
        color: calendar_record.color
      )
    end

    render json: all_calendars
  end

  def calendar
  end

  def forgot_password
  end

  def get_involved
  end

  def resources
  end

  def join_team_program
    if signed_in?
      if current_user.programs.exists?(program_type: Program::TEAMS)
        flash[:alert] = 'You are already part of the Teams Program.'
      else
        current_user.programs.create(program_type: Program::TEAMS)
        flash[
          :notice
        ] = 'You have successfully joined the Teams Program! See below for more information.'
      end
    else
      flash[:alert] = 'You need to sign in to join the Teams Program.'
    end
    redirect_to root_path
  end

  def reset_password
    unless verify_recaptcha
      flash[:alert] = 'There was a problem with the captcha, please try again.'
      redirect_to root_path
      return
    end
    if params[:email].present?
      if User.find_by_email(params[:email]).present?
        @user = User.find_by(email: params[:email])
        user_hash = Rails.application.message_verifier(:user).generate(@user.id)
        expiry_date_hash =
          Rails.application.message_verifier(:user).generate(1.day.from_now)
        MsrMailer.forgot_password(
          params[:email],
          user_hash,
          expiry_date_hash
        ).deliver_now
      end
      flash[
        :notice
      ] = 'A reset link email has been sent to the email if the account exists.'
    else
      flash[:alert] = 'There was a problem with, please try again.'
    end
    redirect_to root_path
  end

  def report_repository
    if signed_in?
      repository = Repository.find params[:repository_id]
      user = current_user
      MsrMailer.repo_report(repository, user).deliver_now
      flash[:alert] = 'Repository has been reported'
    else
      flash[:alert] = 'Please login if you wish to report this repository'
    end
    redirect_back(fallback_location: root_path)
  end

  private

  def home_makerstore_links
    access_token =
      Rails.application.credentials[Rails.env.to_sym][:shopify][:password]
    shop_url = 'uottawa-makerspace.myshopify.com'
    sess =
      ShopifyAPI::Auth::Session.new(shop: shop_url, access_token: access_token)
    client = ShopifyAPI::Clients::Graphql::Admin.new(session: sess)

    query = <<~QUERY
query {
  collections(first: 8) {
      nodes {
        id
        handle
        #onlineStoreUrl
        description
        title
        image {
          url
        }
      }
  }
}
QUERY
    items = client.query(query: query)
    if items.code == 200
      items.body['data']['collections']['nodes'].map do |node|
        {
          'title' => node['title'],
          # HACK: Asking for the onlineStoreUrl errors out,
          # so try and make it yourself from the handle
          #"url" => node['onlineStoreUrl'],
          'url' => "https://makerstore.ca/collections/#{node['handle']}",
          'image' => node['image']['url']
        }
      end
    else
      []
    end
  rescue StandardError
    []
  end
end
