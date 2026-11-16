# frozen_string_literal: true

# DELETE /project_proposals/:project_proposal_id/semester: removes the season and year a proposal is
# active for. Admins only, like setting them.
class ProjectProposals::SemestersController < AdminAreaController
  def destroy
    proposal = ProjectProposal.find_by_param(params[:project_proposal_id])
    return redirect_to(project_proposals_path, alert: I18n.t("errors.proposals.not_found")) unless proposal

    if proposal.clear_semester
      redirect_to project_proposal_path(proposal), notice: I18n.t("project_proposal.admin.semester_cleared")
    else
      redirect_to project_proposal_path(proposal), alert: I18n.t("errors.proposals.semester_not_cleared")
    end
  end
end
