# frozen_string_literal: true

require "rails_helper"

# Chunk 17: Admin::SettingsController (< AdminAreaController, ensure_admin:
# anyone who is not an admin is redirected to "/" with NO flash). Every action
# is a mutation of a lookup table (category/area/equipment options, courses,
# card readers, canned job-order messages, featured repositories).
RSpec.describe "Admin settings", type: :request do
  let(:all_calls) do
    {
      index: -> { get admin_settings_path },
      add_category: -> { post add_category_admin_settings_path, params: { category_option: { name: "Robots" } } },
      add_area: -> { post add_area_admin_settings_path, params: { area_option: { name: "Basement" } } },
      add_equipment: -> { post add_equipment_admin_settings_path, params: { equipment_option: { name: "Laser" } } },
      add_course: -> { post add_course_admin_settings_path, params: { name: "ENG1000" } },
      remove_course: -> { delete remove_course_admin_settings_path, params: { id: course.id } },
      rename_course: -> { patch rename_course_admin_settings_path, params: { id: course.id, name: "Renamed" } },
      remove_category: -> { post remove_category_admin_settings_path, params: { remove_category: category.id } },
      remove_area: -> { post remove_area_admin_settings_path, params: { remove_area: area.id } },
      remove_equipment: -> { post remove_equipment_admin_settings_path, params: { remove_equipment: equipment.id } },
      remove_pi: -> { post remove_pi_admin_settings_path, params: { remove_pi: reader.id } },
      rename_equipment: -> { post rename_equipment_admin_settings_path, params: { rename_equipment: equipment.id, equipment_option: { name: "X" } } },
      processed: -> { patch update_job_order_processed_admin_settings_path, params: { job_order_message: { message: "hacked" } } },
      print_failed: -> { patch update_print_failed_message_admin_settings_path, params: { job_order_message: { message: "hacked" } } },
      pin: -> { patch pin_unpin_repository_admin_settings_path, params: { repository_id: repo.id } }
    }
  end

  let!(:course) { CourseName.create!(name: "ENG0001") }
  let!(:category) { CategoryOption.create!(name: "Drones") }
  let!(:area) { AreaOption.create!(name: "Attic") }
  let!(:equipment) { EquipmentOption.create!(name: "Mill") }
  let!(:reader) { PiReader.create!(pi_mac_address: "aa:bb:cc:dd:ee:ff", pi_location: "Door") }
  let!(:processed_msg) { JobOrderMessage.create!(name: "processed", message: "Done") }
  let!(:repo) { create(:repository) }

  def snapshot
    [CourseName.pluck(:name), CategoryOption.pluck(:name), AreaOption.pluck(:name), EquipmentOption.pluck(:name),
     PiReader.count, JobOrderMessage.pluck(:name, :message).sort, repo.reload.featured]
  end

  describe "authorization" do
    it "bounces guest, regular user and staff to root on every action, changing nothing" do
      before = snapshot
      %i[guest regular staff].each do |role|
        sign_in_as(role)
        all_calls.each do |name, call|
          instance_exec(&call)
          expect(response).to redirect_to("/"), "#{name} as #{role}: #{response.status}"
        end
        post logout_path
      end
      expect(snapshot).to eq(before)
    end

    it "renders the settings page for an admin" do
      sign_in_as(:admin)
      get admin_settings_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Drones", "Attic", "Mill")
    end

    it "answers 404 for submit_pi (route exists, action was commented out)" do
      sign_in_as(:admin)
      post submit_pi_admin_settings_path
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in_as(:admin) }

    it "adds and removes a category option" do
      expect { instance_exec(&all_calls[:add_category]) }.to change(CategoryOption, :count).by(1)
      expect(response).to redirect_to(admin_settings_path)
      expect(flash[:notice]).to eq("Category added successfully!")
      expect { instance_exec(&all_calls[:remove_category]) }.to change(CategoryOption, :count).by(-1)
      expect(flash[:notice]).to eq("Category removed successfully!")
    end

    it "rejects a blank category/area/equipment name with an alert" do
      post add_category_admin_settings_path, params: { category_option: { name: "" } }
      expect(flash[:alert]).to eq("Invalid category name.")
      post add_area_admin_settings_path, params: { area_option: { name: "" } }
      expect(flash[:alert]).to eq("Invalid area name.")
      post add_equipment_admin_settings_path, params: { equipment_option: { name: "" } }
      expect(flash[:alert]).to eq("Invalid equipment name.")
      expect(CategoryOption.count).to eq(1)
    end

    # WART(D-P18): add_* read params[:x][:name] without a guard, so a request missing the wrapper param is a 500 NoMethodError instead of a clean alert
    it "answers 500 when the wrapper param is missing" do
      post add_category_admin_settings_path
      expect(response).to have_http_status(:internal_server_error)
    end

    it "adds and removes an area option" do
      expect { instance_exec(&all_calls[:add_area]) }.to change(AreaOption, :count).by(1)
      expect(flash[:notice]).to eq("Area added successfully!")
      expect { instance_exec(&all_calls[:remove_area]) }.to change(AreaOption, :count).by(-1)
    end

    it "adds, renames and removes equipment options" do
      expect { instance_exec(&all_calls[:add_equipment]) }.to change(EquipmentOption, :count).by(1)
      post rename_equipment_admin_settings_path, params: { rename_equipment: equipment.id, equipment_option: { name: "Lathe" } }
      expect(flash[:notice]).to eq("Equipment renamed successfully!")
      expect(equipment.reload.name).to eq("Lathe")
      post rename_equipment_admin_settings_path, params: { rename_equipment: "", equipment_option: { name: "Lathe" } }
      expect(flash[:alert]).to eq("Please select a piece of equipment.")
      expect { instance_exec(&all_calls[:remove_equipment]) }.to change(EquipmentOption, :count).by(-1)
    end

    # WART(D-P19): remove_* with the select left unset (param absent, not "") skips the guard and reports success while deleting nothing
    it "claims success when no option id was submitted" do
      expect { post remove_category_admin_settings_path }.not_to change(CategoryOption, :count)
      expect(flash[:notice]).to eq("Category removed successfully!")
      post remove_category_admin_settings_path, params: { remove_category: "" }
      expect(flash[:alert]).to eq("Please select a category.")
    end

    it "claims success when the id to remove does not exist" do
      post remove_area_admin_settings_path, params: { remove_area: 0 }
      expect(flash[:notice]).to eq("Area removed successfully!")
    end

    it "removes a card reader" do
      expect { instance_exec(&all_calls[:remove_pi]) }.to change(PiReader, :count).by(-1)
      expect(flash[:notice]).to eq("Card reader removed successfully!")
      post remove_pi_admin_settings_path, params: { remove_pi: "" }
      expect(flash[:alert]).to eq("Please select a card reader.")
    end

    it "adds, renames and removes courses" do
      expect { instance_exec(&all_calls[:add_course]) }.to change(CourseName, :count).by(1)
      expect(flash[:notice]).to eq("Course added successfully!")
      post add_course_admin_settings_path, params: { name: "ENG1000" }
      expect(flash[:alert]).to eq("Input is invalid")
      instance_exec(&all_calls[:rename_course])
      expect(course.reload.name).to eq("Renamed")
      expect(flash[:notice]).to eq("Course updated successfully")
      patch rename_course_admin_settings_path, params: { id: course.id, name: "" }
      expect(flash[:alert]).to eq("There was an issue trying to rename the course")
      expect { instance_exec(&all_calls[:remove_course]) }.to change(CourseName, :count).by(-1)
      expect(flash[:notice]).to eq("Course removed successfully")
    end

    it "404s for an unknown course id" do
      delete remove_course_admin_settings_path, params: { id: 0 }
      expect(response).to have_http_status(:not_found)
    end

    it "updates the canned job-order messages" do
      patch update_job_order_processed_admin_settings_path, params: { job_order_message: { message: "All good" } }
      expect(processed_msg.reload.message).to eq("All good")
      expect(flash[:notice]).to eq("Message updated successfully!")
      patch update_job_order_processed_admin_settings_path, params: { job_order_message: { message: "" } }
      expect(flash[:alert]).to eq("Message update failed.")
      patch update_job_order_processed_admin_settings_path
      expect(flash[:alert]).to eq("Please enter a message.")

      patch update_print_failed_message_admin_settings_path, params: { job_order_message: { message: "Oops" } }
      expect(JobOrderMessage.print_failed.message).to eq("Oops")
      expect(flash[:notice]).to eq("Message updated successfully!")
    end

    it "answers 500 when the 'processed' message row does not exist" do
      processed_msg.destroy
      patch update_job_order_processed_admin_settings_path, params: { job_order_message: { message: "x" } }
      expect(response).to have_http_status(:internal_server_error)
    end

    it "toggles featured on a repository and redirects back" do
      patch pin_unpin_repository_admin_settings_path, params: { repository_id: repo.id },
                                                      headers: { "HTTP_REFERER" => "http://www.example.com/x" }
      expect(response).to redirect_to("http://www.example.com/x")
      expect(repo.reload.featured).to be(true)
      expect(flash[:notice]).to eq("Successfully Featured repository")
      patch pin_unpin_repository_admin_settings_path, params: { repository_id: repo.id }
      expect(repo.reload.featured).to be(false)
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Successfully Unfeatured repository")
    end

    it "redirects with the exception message when repository_id is missing, 500 when unknown" do
      patch pin_unpin_repository_admin_settings_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/repository_id/)
      patch pin_unpin_repository_admin_settings_path, params: { repository_id: 0 }
      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
