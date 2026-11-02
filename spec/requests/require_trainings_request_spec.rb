require "rails_helper"

# Chunk 12: RequireTrainingsController (training prerequisites of volunteer
# tasks). Inherits VolunteerTasksController#grant_access: staff or admin only,
# signed-in others are bounced to root with "You cannot access this area.";
# guests are sent to login.

RSpec.describe "Require trainings", type: :request do
  let(:task) { create(:volunteer_task) }
  let(:training) { create(:training) }
  let(:params) { { require_training: { volunteer_task_id: task.id, training_id: training.id } } }
  let(:back) { { "HTTP_REFERER" => "http://www.example.com/volunteer_tasks" } }

  it "sends a guest to login on create and remove and changes nothing" do
    existing = RequireTraining.create!(volunteer_task: task, training: training)
    expect { post require_trainings_path, params: params }.not_to change(RequireTraining, :count)
    expect(response.location).to include("/login")
    expect { post remove_trainings_require_trainings_path, params: params }.not_to change(RequireTraining, :count)
    expect(response.location).to include("/login")
    expect(RequireTraining.exists?(existing.id)).to be(true)
  end

  %i[regular volunteer].each do |role|
    it "bounces a #{role} on create and remove and changes nothing" do
      existing = RequireTraining.create!(volunteer_task: task, training: training)
      sign_in_as(role)
      expect { post require_trainings_path, params: params }.not_to change(RequireTraining, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
      expect { post remove_trainings_require_trainings_path, params: params }.not_to change(RequireTraining, :count)
      expect(response).to redirect_to(root_path)
      expect(RequireTraining.exists?(existing.id)).to be(true)
    end
  end

  %i[staff admin].each do |role|
    context "as #{role}" do
      before { sign_in_as(role) }

      it "creates the requirement and redirects back with a notice" do
        expect { post require_trainings_path, params: params, headers: back }.to change(RequireTraining, :count).by(1)
        expect(response).to redirect_to("/volunteer_tasks")
        expect(flash[:notice]).to eq("You've successfully added a required training for this volunteer task.")
        expect(task.require_trainings.map(&:training)).to eq([training])
      end

      it "falls back to the task page when there is no referer" do
        post require_trainings_path, params: params
        expect(response).to redirect_to(volunteer_task_path(task))
      end

      it "redirects back with a 'Something went wrong' notice when the training is missing" do
        invalid = { require_training: { volunteer_task_id: task.id, training_id: "" } }
        expect { post require_trainings_path, params: invalid, headers: back }
          .not_to change(RequireTraining, :count)
        expect(response).to redirect_to("/volunteer_tasks")
        expect(flash[:notice]).to eq("Something went wrong")
      end

      it "falls back to the task page when a failed create has no referer" do
        invalid = { require_training: { volunteer_task_id: task.id, training_id: "" } }
        post require_trainings_path, params: invalid
        expect(response).to redirect_to(volunteer_task_path(task))
        expect(flash[:notice]).to eq("Something went wrong")
      end

      it "allows the same training twice on a task (no uniqueness)" do
        post require_trainings_path, params: params
        expect { post require_trainings_path, params: params }.to change(RequireTraining, :count).by(1)
      end

      it "redirects to root with the ParameterMissing message when the key is absent" do
        post require_trainings_path, params: {}
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("require_training")
      end
    end
  end

  describe "POST /require_trainings/remove_trainings" do
    let!(:requirement) { RequireTraining.create!(volunteer_task: task, training: training) }

    it "deletes the requirement for staff and redirects back with a notice" do
      sign_in_as(:staff)
      expect { post remove_trainings_require_trainings_path, params: params, headers: back }
        .to change(RequireTraining, :count).by(-1)
      expect(response).to redirect_to("/volunteer_tasks")
      expect(flash[:notice]).to eq("You've successfully deleted this required training")
    end

    it "alerts when no such requirement exists" do
      sign_in_as(:admin)
      other = create(:training)
      expect { post remove_trainings_require_trainings_path, params: { require_training: { volunteer_task_id: task.id, training_id: other.id } } }
        .not_to change(RequireTraining, :count)
      expect(flash[:alert]).to eq("Something went wrong")
    end
  end
end
