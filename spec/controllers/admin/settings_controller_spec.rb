require 'rails_helper'

RSpec.describe Admin::SettingsController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
  end

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @admin.id
  end

  describe 'GET /index' do
    context 'logged as regular user' do
      it 'should return 200' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end

    context 'logged as admin' do
      it 'should return 200' do
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /add_category' do

    context 'add category' do

      it 'should create the category' do
        post :add_category, params: {category_option: {name: "Abc"}}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:notice]).to eq('Category added successfully!')
      end

      it 'should not create the category' do
        post :add_category, params: {category_option: {name: ""}}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Invalid category name.')
      end

    end

  end

  describe 'POST /add_area' do

    context 'add area' do

      it 'should create the area' do
        post :add_area, params: {area_option: {name: "Abc"}}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:notice]).to eq('Area added successfully!')
      end

      it 'should not create the area' do
        post :add_area, params: {area_option: {name: ""}}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Invalid area name.')
      end

    end

  end

  describe 'POST /add_printer' do

    context 'add printer' do

      it 'should add the printer' do
        post :add_printer, params: {printer: {model: "Ultimaker 2+", number: "UM2P-01"}}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:notice]).to eq('Printer added successfully!')
      end

      it 'should not add the printer' do
        post :add_printer, params: {printer: {model: "Ultimaker 2+", number: ""}}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Invalid printer model or number')
      end

      it 'should not add the printer' do
        post :add_printer, params: {printer: {model: "", number: "UM2P-01"}}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Invalid printer model or number')
      end

      it 'should not add the printer' do
        post :add_printer, params: {printer: {model: "", number: ""}}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Invalid printer model or number')
      end

    end

  end

  describe 'POST /remove_category' do

    context 'remove category' do

      it 'should remove the category' do
        category = CategoryOption.create(name: "Abc")
        post :remove_category, params: {remove_category: category.id}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:notice]).to eq('Category removed successfully!')
      end

      it 'should not remove the category' do
        post :remove_category, params: {remove_category: ""}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Please select a category.')
      end

    end

  end

  describe 'POST /remove_area' do

    context 'remove area' do

      it 'should remove the area' do
        area = AreaOption.create(name: "Abc")
        post :remove_area, params: {remove_area: area.id}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:notice]).to eq('Area removed successfully!')
      end

      it 'should not remove the area' do
        post :remove_area, params: {remove_area: ""}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Please select an area.')
      end

    end

  end

  describe 'POST /remove_printer' do

    context 'remove printer' do

      it 'should remove the printer' do
        printer = Printer.create(model: "Ultimaker 2+", number: "UM2P-01")
        post :remove_printer, params: {remove_printer: printer.id}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:notice]).to eq('Printer removed successfully!')
      end

      it 'should not remove the printer' do
        post :remove_printer, params: {remove_printer: ""}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Please select a Printer.')
      end

    end

  end

  describe 'POST /add_equipment' do

    context 'add equipment' do

      it 'should add an equipment' do
        post :add_equipment, params: { equipment_option: {name: "3d printer"} }
        expect(response).to redirect_to admin_settings_path
        expect(flash[:notice]).to eq('Equipment added successfully!')
      end

      it 'should not add a equipement' do
        post :add_equipment, params: { equipment_option: {name: ""} }
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Invalid equipment name.')
      end

    end

  end

  describe 'POST /rename_equipment' do

    context 'rename equipment' do

      it 'should rename an equipment' do
        equipement = EquipmentOption.create(name: "3d printer")
        post :rename_equipment, params: { equipment_option: {name: "Laser cutter"}, rename_equipment: equipement.id }
        expect(response).to redirect_to admin_settings_path
        expect(flash[:notice]).to eq('Equipment renamed successfully!')
      end

      it 'should not rename the equipement' do
        post :rename_equipment, params: { equipment_option: {name: ""}}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Invalid equipment name.')
      end

      it 'should not rename the equipement' do
        post :rename_equipment, params: { equipment_option: {name: "3D Printer"}, rename_equipment: "" }
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Please select a piece of equipment.')
      end

    end

  end

  describe 'POST /remove_equipment' do

    context 'remove equipment' do

      it 'should remove an equipment' do
        equipement = EquipmentOption.create(name: "3d printer")
        post :remove_equipment, params: { remove_equipment: equipement.id}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:notice]).to eq('Equipment removed successfully!')
      end

      it 'should remove add a equipement' do
        post :remove_equipment, params: { remove_equipment: "" }
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Please select a piece of equipment.')
      end

    end

  end

  describe 'POST /remove_pi' do

    context 'remove pi' do

      it 'should remove pi' do
        space = create(:space)
        pi = PiReader.create(pi_location: space.id, pi_mac_address: "12:34:56:78:90")
        post :remove_pi, params: { remove_pi: pi.id}
        expect(response).to redirect_to admin_settings_path
        expect(flash[:notice]).to eq('Card reader removed successfully!')
      end

      it 'should not remove pi' do
        post :remove_pi, params: { remove_pi: "" }
        expect(response).to redirect_to admin_settings_path
        expect(flash[:alert]).to eq('Please select a card reader.')
      end

    end

  end

  describe 'POST /pin_unpin_repository' do

    context 'pin unpin repository' do

      it 'should pin a repository' do
        repo = create(:repository)
        post :pin_unpin_repository, params: { repository_id: repo.id}
        expect(response).to have_http_status(302)
        expect(flash[:notice]).to eq("Featured: #{Repository.find(repo.id).featured}")
      end

      it 'should unpin a repository' do
        repo = create(:repository)
        Repository.find(repo.id).update(featured: true)
        post :pin_unpin_repository, params: { repository_id: repo.id}
        expect(response).to have_http_status(302)
        expect(flash[:notice]).to eq("Featured: #{Repository.find(repo.id).featured}")
      end

    end

  end

end
