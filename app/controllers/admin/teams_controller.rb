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

  def create
    @team = Team.new(team_params)

    captain = User.find_by(id: params[:captain])

    if captain.nil?
      redirect_to new_admin_team_path, alert: "Please select a captain"
    else
      if @team.save
        TeamMembership.create(
          user_id: captain.id,
          team_id: @team.id,
          role: :captain
        )
        redirect_to admin_teams_path, notice: "Successfully created team"
      else
        redirect_to new_admin_team_path,
                    alert: "Something went wrong while creating the team"
      end
    end
  end

  def update
    if @team.update(team_params)
      redirect_to admin_teams_path, notice: "Successfully updated team"
    else
      redirect_to edit_admin_team_path,
                  alert: "Something went wrong when trying to update the team."
    end
  end

  def add_member
    member = User.find_by(id: params[:member_id])

    if member.nil?
      flash[:alert] = "Couldn't find user, please try again later."
    else
      tm =
        TeamMembership.new(
          user_id: member.id,
          team_id: @team.id,
          role: params[:role]
        )

      if tm.save
        flash[:notice] = "Successfully added user."
      else
        flash[:alert] = "Something went wrong while trying to add the user."
      end
    end

    redirect_to admin_team_path(@team.id)
  end

  def remove_member
  end

  def promote_member
  end

  def demote_member
  end

  private

  def team_params
    params.require(:team).permit(:name)
  end

  def set_team
    @team = Team.find_by(id: params[:id])

    redirect_to admin_teams_path, alert: "Could not find team" if @team.nil?
  end
end
