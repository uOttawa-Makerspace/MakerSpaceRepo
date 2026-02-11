require "rails_helper"

RSpec.describe SearchController, type: :controller do
  describe "GET /explore" do
    context "explore" do
      before(:all) { (0..15).each { create(:repository) } }

      it "should get a 200" do
        get :explore
        expect(response).to have_http_status(:success)
      end

      it "should get a 200 on the second page" do
        get :explore, params: { page: 2 }
        expect(response).to have_http_status(:success)
      end

      it "should sort by newest" do
        get :explore, params: { sort: "newest" }
        expect(response).to have_http_status(:success)
      end

      it "should sort by most likes" do
        get :explore, params: { sort: "most_likes" }
        expect(response).to have_http_status(:success)
      end

      it "should sort by most makes" do
        get :explore, params: { sort: "most_makes" }
        expect(response).to have_http_status(:success)
      end

      it "should sort by recently_updated" do
        get :explore, params: { sort: "recently_updated" }
        expect(response).to have_http_status(:success)
      end

      it "should show only repositories from the Internet of Things category" do
        CategoryOption.create(name: "Internet of Things")
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "Internet of Things")
        get :explore, params: { category: "internet-of-things" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should show only repositories from the Course-related Projects category" do
        CategoryOption.create(name: "Course-related Projects")
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "Course-related Projects")
        get :explore, params: { category: "course-related-projects" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should show only repositories from the GNG2101/GNG2501 category" do
        CategoryOption.create(name: "GNG2101/GNG2501")
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "GNG2101/GNG2501")
        get :explore, params: { category: "gng2101/gng2501" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should show only repositories from the GNG1103/GNG1503 category" do
        CategoryOption.create(name: "GNG1103/GNG1503")
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "GNG1103/GNG1503")
        get :explore, params: { category: "gng1103/gng1503" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should show only repositories from the Health Sciences category" do
        CategoryOption.create(name: "Health Sciences")
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "Health Sciences")
        get :explore, params: { category: "health-sciences" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should show only repositories from the Wearable category" do
        CategoryOption.create(name: "Wearable")
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "Wearable")
        get :explore, params: { category: "wearable" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should show only repositories from the Mobile Development category" do
        CategoryOption.create(name: "Mobile Development")
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "Mobile Development")
        get :explore, params: { category: "mobile-development" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should show only repositories from the Virtual Reality category" do
        CategoryOption.create(name: "Virtual Reality")
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "Virtual Reality")
        get :explore, params: { category: "virtual-reality" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should show only repositories from the Other Projects category" do
        CategoryOption.create(name: "Other Projects")
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "Other Projects")
        get :explore, params: { category: "other-projects" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should show only repositories from the uOttawa Team Projects category" do
        CategoryOption.create(name: "uOttawa Team Projects")
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "uOttawa Team Projects")
        get :explore, params: { category: "uottawa-team-projects" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should show only repositories from the Internet of Things category and sort by most likes" do
        CategoryOption.create(name: "Internet of Things")
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "Internet of Things")
        get :explore,
            params: {
              category: "internet-of-things",
              sort: "most_likes"
            }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /search" do
    context "search" do
      it "should search for the right result" do
        create(:repository)
        create(
          :repository,
          description:
            "Donec malesuada lacus lorem, ac finibus nibh ultrices quis. Duis dignissim nisl tristique convallis dignissim."
        )
        get :search,
            params: {
              q: "Donec malesuada lacus lorem, ac finibus nibh ultrices quis."
            }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should get no results" do
        create(:repository)
        create(:repository)
        create(:repository)
        get :search,
            params: {
              q: "Donec malesuada lacus lorem, ac finibus nibh ultrices quis."
            }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(0)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /category" do
    context "category" do
      before(:each) do
        CategoryOption.create(name: "Internet of Things")
        create(:repository)
        create(:repository)
      end

      it "should get all the repo with the right category" do
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "Internet of Things")
        get :explore, params: { category: "internet-of-things" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should get no results" do
        get :explore, params: { category: "internet-of-things" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(0)
        expect(response).to have_http_status(:success)
      end

      it "should get the featured results" do
        repo = create(:repository, featured: true)
        Category.create(repository_id: repo.id, name: "Internet of Things")
        get :explore,
            params: {
              category: "internet-of-things",
              featured: "yes"
            }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /equipment" do
    context "equipment" do
      before(:each) do
        EquipmentOption.create(name: "3D Printer")
        create(:repository)
        create(:repository)
      end

      it "should get all the repo with the right category" do
        repo = create(:repository)
        Equipment.create(repository_id: repo.id, name: "3D Printer")
        get :equipment, params: { slug: "3D Printer" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it "should get no results" do
        get :equipment, params: { slug: "internet-of-things" }
        expect(@controller.instance_variable_get(:@repositories).count).to eq(0)
        expect(response).to have_http_status(:success)
      end
    end
  end
end