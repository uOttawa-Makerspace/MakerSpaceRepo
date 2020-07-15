require 'rails_helper'
include BCrypt

RSpec.describe Repository, type: :model do

  describe 'Association' do

    context 'has_many' do
      it { should have_many(:photos) }
      it { should have_many(:repo_files) }
      it { should have_many(:categories) }
      it { should have_many(:equipments) }
      it { should have_many(:comments) }
      it { should have_many(:likes) }
      it { should have_many(:makes) }
    end

    context 'belongs_to' do
      it { should belong_to(:project_proposal) }
      it { should belong_to(:parent) }
    end

    context 'has_and_belongs_to_many' do
      it { should have_and_belong_to_many(:users) }
    end

  end

  describe "Scopes" do

    context "public_repo" do

      it 'should only get private repos' do
        create(:repository)
        create(:repository, :private)
        repo_count = Repository.all.count
        expect(Repository.public_repos.count).to eq(repo_count - 1)
      end

    end

  end

  describe "Validations" do

    context "title" do
      it { should_not allow_value("gds%%$32").for(:title).with_message("Invalid project title") }
      it { should allow_value("johndoe").for(:title) }
      it { should validate_presence_of(:title).with_message("Project title is required.") }
        #it { should validate_uniqueness_of(:title).scoped_to(:user_username).with_message("Project title is already in use.") }
    end

    context "share type" do
      it { should_not allow_value("Nothing").for(:share_type) }
      it { should allow_value('public', 'private').for(:share_type) }
      it { should validate_presence_of(:share_type).with_message("Is your project public or private?") }
    end

    context 'password private' do
      subject { build(:repository, :private) }
      it { should validate_presence_of(:password).with_message("Password is required for private projects") }
    end

    context "password public" do
      subject { build(:repository) }
      it { should_not validate_presence_of(:password) }
    end

  end

  describe "Before save" do

    context 'youtube_link' do

      it 'should make youtube_link nil' do
        pp = create(:repository)
        expect(pp.youtube_link).to be(nil)
      end

      it 'should return nil (bad link)' do
        pp = create(:repository, :broken_link)
        expect(pp.youtube_link).to be(nil)
      end

      it 'should return nil (good link)' do
        pp = create(:repository, :working_link)
        expect(pp.youtube_link).to eq("https://www.youtube.com/watch?v=AbcdeFGHIJLK")
      end

    end

    context 'self.slug' do

      it 'should get the right slug' do
        repo = create(:repository, title: "ABC Abc")
        expect(repo.slug).to eq("abc-abc")
      end

    end

  end


  describe "before destroy" do

    context "reputation" do

      it 'should lower reputation by 25' do
        user = create(:user, :regular_user)
        repo = create(:repository)
        Repository.find(repo.id).users << User.find(user.id)
        Repository.find(repo.id).destroy
        expect(User.last.reputation).to eq(-25)
      end

    end

  end

  describe "#scopes" do

    context '#between_dates_picked' do

      it 'should return one' do
        create(:repository, created_at: '2017-07-07 19:15:39.406247')
        start_date = DateTime.new(2016,2,3,4,5,6)
        end_date = DateTime.new(2018,2,3,4,5,6)
        expect(Repository.between_dates_picked(start_date, end_date).count).to eq(1)
      end

      it 'should return one' do
        create(:repository, created_at: '2020-07-07 19:15:39.406247')
        start_date = DateTime.new(2019,2,3,4,5,6)
        end_date = DateTime.new(2020,2,3,4,5,6)
        expect(Repository.between_dates_picked(start_date, end_date).count).to eq(0)
      end

    end

  end

  describe "methods" do

    context "#private?" do

      it "shoudn't be private" do
        repo = create(:repository)
        expect(repo.private?).to be_falsey
      end

      it "should be private" do
        repo = create(:repository, :private)
        expect(repo.private?).to be_truthy
      end

    end

    context '#authenticate' do

      before(:all) do
        create(:repository, :private)
      end

      it 'should return nothing' do
        expect(Repository.authenticate(Repository.last.slug, 'somethingelse')).to be_falsey
      end

      it 'should return the user' do
        create(:repository, :private)
        expect(Repository.authenticate(Repository.last.slug, 'abc')).to be_truthy
      end

    end

    context "#pword=" do

      it 'should return a new password' do
        repo = create(:repository, :private)
        @repository = Repository.find(repo.id)
        @repository.pword = "abcd"
        @repository.save
        expect(Repository.last.password).not_to eq("$2a$12$fJ1zqqOdQVXHt6GZVFWyQu2o4ZUU3KxzLkl1JJSDT0KbhfnoGUvg2")
      end

    end

  end

end
