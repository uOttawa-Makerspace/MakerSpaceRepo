# frozen_string_literal: true

require "rails_helper"

# The new/edit form's SCORM switch starts from whether the module has a package, and a failed save shows it as
# submitted. Lists of modules do not look up each module's package unless the page shows it.
RSpec.describe "Learning area SCORM switch", type: :request do
  let(:training) { create(:training) }

  def switch_checked?
    box = Capybara.string(response.body).find("input[type=checkbox][name='learning_module[scorm_enabled]']")
    box[:checked].present?
  end

  def attachment_selects(&block) = selects_on("active_storage_attachments", &block)

  describe "the edit form" do
    before { sign_in_as(:admin) }

    it "starts with the switch on for a module that has a package" do
      lm = create(:learning_module, :with_scorm_object, training: training)
      get edit_learning_area_path(lm)
      expect(switch_checked?).to be(true)
    end

    it "starts with the switch off for a module that has no package" do
      lm = create(:learning_module, training: training)
      get edit_learning_area_path(lm)
      expect(switch_checked?).to be(false)
    end

    it "starts with the switch off on the new form" do
      get new_learning_area_path
      expect(switch_checked?).to be(false)
    end
  end

  describe "a failed save" do
    before { sign_in_as(:admin) }

    it "shows the switch on after a failed update that turned it on with a package" do
      lm = create(:learning_module, training: training)
      patch learning_area_path(lm),
            params: { learning_module: { title: "", scorm_enabled: "1", scorm_package: ScormZipHelper.create_scorm_zip } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(switch_checked?).to be(true)
    end

    it "shows the switch off after a failed update that turned it off and removed the package" do
      lm = create(:learning_module, :with_scorm_object, training: training)
      patch learning_area_path(lm), params: { learning_module: { title: "", scorm_enabled: "0", scorm_package: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(switch_checked?).to be(false)
      expect(lm.reload.scorm_package).to be_attached
    end

    it "shows the switch as submitted after a failed update that left the package alone" do
      lm = create(:learning_module, :with_scorm_object, training: training)
      patch learning_area_path(lm), params: { learning_module: { title: "", scorm_enabled: "0" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(switch_checked?).to be(false)
    end

    it "shows the switch on after a failed create with a package" do
      post learning_area_index_path,
           params: { learning_module: { title: "", training_id: training.id, level: "Beginner", scorm_enabled: "1",
                                        scorm_package: ScormZipHelper.create_scorm_zip } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(switch_checked?).to be(true)
    end

    it "shows the switch off after a failed create without a package" do
      post learning_area_index_path,
           params: { learning_module: { title: "", training_id: training.id, level: "Beginner", scorm_enabled: "0" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(switch_checked?).to be(false)
    end
  end

  describe "lists of modules" do
    it "loads modules without looking up their packages" do
      create_list(:learning_module, 3, training: training)
      expect(attachment_selects { LearningModule.all.to_a }).to be_empty
    end

    it "reads the index's attachments in a number of queries that does not grow with its modules" do
      create(:learning_module, :with_scorm_object, training: training)
      sign_in_as(:regular)
      get learning_area_index_path
      one = attachment_selects { get learning_area_index_path }.size
      create(:learning_module, :with_scorm_object, training: training)
      create(:learning_module, training: training)
      many = attachment_selects { get learning_area_index_path }.size
      expect(response).to have_http_status(:ok)
      expect(many).to eq(one)
    end
  end
end
