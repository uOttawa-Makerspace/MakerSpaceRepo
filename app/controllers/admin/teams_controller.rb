class Admin::TeamsController < AdminAreaController
  before_action :set_team,
                only: %i[
                  show
                  edit
                  update
                  add_member
                  remove_member
                  promote_member
                  demote_member
                ]
  before_action :set_team_member,
                only: %i[add_member remove_member promote_member demote_member]

  def index
    @teams = Team.order(name: :asc)
  end

  def show
    @team_members =
      @team.team_memberships.order(role: :desc).joins(:user).order("users.name")
  end

  def new
    @team = Team.new
  end

  def edit
    @captain_select = []
    captain = @team.captain
    @captain_select << [
      captain.name + " (" + captain.username + ")",
      captain.id
    ]

    team_memberships =
      @team
        .team_memberships
        .except(:captain)
        .joins(:user)
        .order("LOWER(users.name) ASC")
    team_memberships.each do |tm|
      @captain_select << [
        tm.user.name + " (" + tm.user.username + ")",
        tm.user.id
      ]
    end
  end

  def create
    @team = Team.new(team_params)

    captain = User.find_by(id: params[:captain])

    if captain.nil?
      redirect_to new_admin_team_path, alert: I18n.t("admin_pages.teams.flash.select_captain")
    else
      if @team.save
        TeamMembership.create(
          user_id: captain.id,
          team_id: @team.id,
          role: :captain
        )
        redirect_to admin_teams_path, notice: I18n.t("admin_pages.teams.flash.created")
      else
        redirect_to new_admin_team_path,
                    alert: validation_message(@team, "errors.admin.teams.not_created")
      end
    end
  end

  def update
    tm = @team.team_memberships.find_by(user_id: params[:captain])
    if tm.nil?
      return(
        redirect_to edit_admin_team_path,
                    alert: I18n.t("admin_pages.teams.flash.captain_not_member")
      )
    end

    owner_tm = @team.team_memberships.where(role: :captain).first

    if @team.update(team_params)
      unless tm.eql?(owner_tm)
        owner_tm.update(role: :lead)
        tm.update(role: :captain)
      end

      redirect_to admin_teams_path, notice: I18n.t("admin_pages.teams.flash.updated")
    else
      redirect_to edit_admin_team_path,
                  alert: validation_message(@team, "errors.admin.teams.not_updated")
    end
  end

  def add_member
    if TeamMembership.roles.key?(params[:role])
      tm = TeamMembership.new(user_id: @member.id, team_id: @team.id, role: params[:role])
      flash_write(tm, "teams.member_not_added", I18n.t("admin_pages.teams.flash.member_added")) { tm.save }
    else
      flash[:alert] = I18n.t("errors.admin.teams.role_unknown")
    end

    redirect_to admin_team_path(@team.id)
  end

  def remove_member
    tm = @team.team_memberships.where(user_id: @member.id).first

    if tm.nil?
      flash[:alert] = I18n.t("admin_pages.teams.flash.member_not_in_team")
    elsif tm.role_captain?
      flash[:alert] = I18n.t("admin_pages.teams.flash.captain_not_removable")
    else
      tm.destroy
      flash[:notice] = I18n.t("admin_pages.teams.flash.member_removed")
    end

    redirect_to admin_team_path(@team.id)
  end

  def promote_member
    tm = @team.team_memberships.where(user_id: @member.id).first

    if tm.nil?
      flash[:alert] = I18n.t("admin_pages.teams.flash.member_not_in_team")
    elsif tm.role_regular_member?
      tm.update(role: :lead)
      flash[:notice] = I18n.t("admin_pages.teams.flash.member_promoted")
    else
      flash[:alert] = I18n.t("errors.admin.teams.cannot_promote")
    end

    redirect_to admin_team_path(@team.id)
  end

  def demote_member
    tm = @team.team_memberships.where(user_id: @member.id).first

    if tm.nil?
      flash[:alert] = I18n.t("admin_pages.teams.flash.member_not_in_team")
    elsif tm.role_lead?
      tm.update(role: :regular_member)
      flash[:notice] = I18n.t("admin_pages.teams.flash.member_demoted")
    else
      flash[:alert] = I18n.t("errors.admin.teams.cannot_demote")
    end

    redirect_to admin_team_path(@team.id)
  end

  private

  def team_params
    params.require(:team).permit(:name)
  end

  def set_team
    @team = Team.find_by(id: params[:id])

    redirect_to admin_teams_path, alert: I18n.t("admin_pages.teams.flash.team_not_found") if @team.nil?
  end

  def set_team_member
    @member = User.find_by(id: params[:member_id])

    redirect_to admin_teams_path, alert: I18n.t("admin_pages.teams.flash.member_not_found") if @member.nil?
  end
end
