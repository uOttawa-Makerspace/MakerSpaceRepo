require 'test_helper'

class ProjectProposalsControllerTest < ActionController::TestCase
  setup do
    @project_proposal = project_proposals(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:project_proposals)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create project_proposal" do
    assert_difference('ProjectProposal.count') do
      post :create, project_proposal: { admin_id: @project_proposal.admin_id, approved: @project_proposal.approved, description: @project_proposal.description, score: @project_proposal.score, title: @project_proposal.title, user_id: @project_proposal.user_id, youtube_link: @project_proposal.youtube_link }
    end

    assert_redirected_to project_proposal_path(assigns(:project_proposal))
  end

  test "should show project_proposal" do
    get :show, id: @project_proposal
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @project_proposal
    assert_response :success
  end

  test "should update project_proposal" do
    patch :update, id: @project_proposal, project_proposal: { admin_id: @project_proposal.admin_id, approved: @project_proposal.approved, description: @project_proposal.description, score: @project_proposal.score, title: @project_proposal.title, user_id: @project_proposal.user_id, youtube_link: @project_proposal.youtube_link }
    assert_redirected_to project_proposal_path(assigns(:project_proposal))
  end

  test "should destroy project_proposal" do
    assert_difference('ProjectProposal.count', -1) do
      delete :destroy, id: @project_proposal
    end

    assert_redirected_to project_proposals_path
  end
end
