# frozen_string_literal: true

require "rails_helper"

# Logged-out explore, category, equipment, repository and profile-listing pages read from the
# locale files: the English page keeps its wording and the same page under ?locale=fr is in
# French. Text is compared with whitespace collapsed, as a browser shows it.
RSpec.describe "Public repository pages in English and French", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, :create_equipement_and_categories, owner: owner, users: [owner], title: "Laser Lamp", license: "Creative Commons - Attribution") }
  let!(:repo_file) do
    RepoFile.create!(repository_id: repo.id, file: Rack::Test::UploadedFile.new(Rails.root.join("spec/support/assets/RepoFile1.pdf"), "application/pdf"))
  end
  let!(:wearable) { Category.create!(name: "Wearable", repository_id: repo.id) }
  let!(:comment) { create(:comment, repository: repo, created_at: 3.hours.ago) }

  def page_text
    Nokogiri::HTML(response.body).at_css("body").text.gsub(/[[:space:]]+/, " ")
  end

  def visit(path, locale, params = {})
    get path, params: params.merge(locale: locale)
    expect(response).to have_http_status(:ok)
    page_text
  end

  describe "explore and search" do
    it "keeps the English wording" do
      text = visit(explore_path, "en")
      expect(text).to include("Explore recent repositories", "Project title or description", "by #{repo.user_username}")
      expect(response.body).to include(%(placeholder="Project title or description..."), %(value="Search"))
      expect(response.body).to include("<title>Explore | MakerRepo</title>")
      expect(text).to include("Internet of Things", "Course-related Projects", "GNG2101/GNG2501", "GNG1103/GNG1503", "Health Sciences", "Wearable", "Mobile Development", "Virtual Reality", "Other Projects", "uOttawa Team Projects")
    end

    it "keeps the English search results wording" do
      text = visit(search_path, "en", q: "Laser")
      expect(text).to include("Search results for Laser")
      expect(response.body).to include('<title>Search results for &quot;Laser&quot; | MakerRepo</title>')
    end

    it "is in French" do
      text = visit(explore_path, "fr")
      expect(text).to include("Parcourir les dépôts récents", "Titre ou description du projet", "par #{repo.user_username}")
      expect(text).not_to include("Explore recent repositories", "Project title", "by #{repo.user_username}")
      expect(response.body).to include('placeholder="Titre ou description du projet..."')
      expect(text).to include("Internet des objets", "Projets liés à un cours", "Sciences de la santé", "Réalité virtuelle", "Autres projets", "Projets d'équipe uOttawa")
      expect(text).not_to include("Course-related Projects", "Other Projects")
    end

    it "shows the French search results" do
      text = visit(search_path, "fr", q: "Laser")
      expect(text).to include("Résultats de recherche pour Laser")
      expect(text).not_to include("Search results")
      expect(response.body).to include('<title>Résultats de recherche pour &quot;Laser&quot; | MakerRepo</title>')
    end

    it "has a French and an English name for every category filter" do
      SearchController::SLUG_TO_CATEGORY_MODEL.each_key do |slug|
        key = "search.explore.categories.#{slug.tr('-/', '__')}"
        expect(I18n.exists?(key, :en)).to be(true), key
        expect(I18n.exists?(key, :fr)).to be(true), key
      end
    end
  end

  describe "category and equipment" do
    it "keeps the English category wording" do
      text = visit(category_path(slug: "wearable"), "en")
      expect(text).to include("All projects", "Featured projects", "Newest / Plus récent", "Most Likes / Plus d'Aimes", "Most Makes / Plus de fabrications", "Recently Updated / Récemment mis à jour")
      expect(text).to include("by #{repo.user_username}", "ago")
      expect(visit(category_path(slug: "wearable"), "en", sort: "most_likes")).to include("Most Likes")
    end

    it "is in French for the category page" do
      text = visit(category_path(slug: "wearable"), "fr")
      expect(text).to include("Tous les projets", "Projets en vedette", "Plus récent", "Plus d'Aimes", "Plus de fabrications", "Récemment mis à jour")
      expect(text).not_to include("All projects", "Featured projects", "Most Likes", "Newest")
      expect(visit(category_path(slug: "wearable"), "fr", sort: "most_likes")).to include("Plus d'Aimes")
    end

    it "keeps the English equipment wording" do
      text = visit(equipment_path(slug: "laser-cutter"), "en")
      expect(text).to include("sort by/trier par", "Newest/Plus récent", "Most Likes/Plus d'Aimes", "Most Makes/Plus de fabrications", "Recently Updated/Récemment mis à jour")
    end

    it "closes the equipment listing before the footer" do
      visit(equipment_path(slug: "laser-cutter"), "en")
      expect(response.body.scan(/<section\b/).size).to eq(response.body.scan(%r{</section>}).size)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#repositories-index #repositories-container")).to be_present
      expect(page.at_css("footer")).to be_present
      expect(page.at_css("#repositories-index footer")).to be_nil
    end

    it "is in French for the equipment page" do
      text = visit(equipment_path(slug: "laser-cutter"), "fr")
      expect(text).to include("trier par", "Plus récent", "Plus d'Aimes")
      expect(text).not_to include("sort by", "Newest", "Most Likes")
    end

    it "labels a featured repository" do
      repo.update_columns(featured: true)
      expect(visit(category_path(slug: "wearable"), "en", featured: "yes")).to include("Featured projects")
    end
  end

  describe "repository page" do
    def repo_url = repository_path(repo.user_username, repo.slug)

    before { repo.update_columns(youtube_link: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") }

    it "keeps the English wording" do
      repo.update_columns(featured: true)
      text = visit(repo_url, "en")
      expect(text).to include("Previous", "Next", "This is a featured project!", "KB", "Project by", "Published on", "Sign in to download", "Comments", "Top votes", "Newest")
      expect(text).to match(/\d+ KB/)
      expect(text).to include("3 hours ago").or include("about 3 hours ago")
      expect(response.body).to include(%(<span class="visually-hidden">Previous</span>), %(<span class="visually-hidden">Next</span>))
      expect(text).to match(/Published on \w{3} [ \d]\d \d{4}/)
    end

    it "is in French" do
      repo.update_columns(featured: true)
      text = visit(repo_url, "fr")
      expect(text).to include("Précédent", "Suivant", "Ce projet est en vedette !", "Ko", "il y a")
      expect(text).not_to include("featured project", " KB", " ago", "Previous")
      expect(text).to match(/Publié le +\d+ \S+ \d{4}/)
    end
  end

  describe "profile repositories" do
    it "keeps the English wording" do
      text = visit(user_path(repo.user_username), "en")
      expect(text).to include("Displaying repositories 1 - 1 of 1 in total", "by #{repo.user_username}")
      expect(text).to include("Reputation")
      expect(visit(user_path(repo.user_username), "en", show: "makes")).to include("#{repo.user_username} doesn't have any makes yet.")
      expect(visit(user_path(repo.user_username), "en", show: "projects_assigned")).to include("#{repo.user_username} doesn't have any joined projects yet.")
    end

    it "keeps the English empty repositories message" do
      other = create(:user, :regular_user)
      expect(visit(user_path(other.username), "en", show: "repositories")).to include("#{other.username} doesn't have any repositories yet.")
    end

    it "is in French" do
      other = create(:user, :regular_user)
      text = visit(user_path(repo.user_username), "fr")
      expect(text).to include("Affichage des dépôts 1 - 1 sur 1 au total", "par #{repo.user_username}")
      expect(text).not_to include("Displaying repositories")
      expect(visit(user_path(other.username), "fr", show: "repositories")).to include("#{other.username} n'a pas encore de dépôts.")
      expect(visit(user_path(other.username), "fr", show: "makes")).to include("#{other.username} n'a pas encore de créations.")
      expect(visit(user_path(other.username), "fr", show: "projects_assigned")).to include("#{other.username} n'a pas encore de projets participés.")
    end
  end
end
