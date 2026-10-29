# frozen_string_literal: true

require "rails_helper"

# Chunk 16: behaviors of the repository/project models not covered by the
# per-model specs (default_scope, zip cache, slug lifecycle, search scopes,
# attachment validation edges, counters).
RSpec.describe "Content models (part 1 characterization)" do
  include ContentSpecHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:owner) { create(:user, :regular_user) }

  describe Repository do
    let!(:repo) { create(:repository, owner: owner, title: "Scope Check", users: [owner]) }

    it "default_scope hides soft-deleted rows from find, where, count, exists? and associations" do
      repo.update_columns(deleted: true)
      expect(Repository.count).to eq(0)
      expect(Repository.exists?(repo.id)).to be(false)
      expect { Repository.find(repo.id) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(Repository.where(user_id: owner.id).to_a).to eq([])
      expect(Repository.unscoped.find(repo.id)).to eq(repo)
      expect(Repository.unscoped.where(deleted: true).count).to eq(1)
    end

    it "a comment's repository association resolves to nil once the repository is soft-deleted (D-C52)" do
      comment = create(:comment, repository: repo)
      repo.update_columns(deleted: true)
      # WART(D-C52): belongs_to goes through the default scope; code that derefs comment.repository (CommentsController#destroy) breaks
      expect(comment.reload.repository).to be_nil
      expect(Comment.count).to eq(1)
    end

    it "soft-deleting does not touch dependents (photos, likes, comments stay)" do
      create(:like, repository: repo)
      repo.update_columns(deleted: true)
      expect([Photo.count, Like.count]).to eq([1, 1])
    end

    it "a make's parent resolves to nil once the original is soft-deleted" do
      child = create(:repository, owner: owner, title: "Child", make_id: repo.id)
      repo.update_columns(deleted: true)
      expect(child.reload.parent).to be_nil
    end

    describe "slug" do
      it "is the bare title slug on create, '<id>.<slug>' after any later save with changes" do
        fresh = create(:repository, owner: owner, title: "Hello, World!")
        expect(fresh.slug).to eq("hello-world")
        fresh.update!(description: "x")
        expect(fresh.slug).to eq("#{fresh.id}.hello-world")
      end

      it "strips non-ASCII letters entirely (accented titles lose characters)" do
        r = create(:repository, owner: owner, title: "Café Table")
        expect(r.slug).to eq("caf-table")
      end

      it "is not unique: two owners can hold the same slug" do
        a = create(:repository, owner: owner, title: "Same")
        b = create(:repository, owner: create(:user), title: "Same")
        expect(a.slug).to eq(b.slug)
      end
    end

    describe "photos validation" do
      it "requires at least one photo" do
        r = Repository.new(owner: owner, title: "No pics", share_type: "public")
        expect(r).not_to be_valid
        expect(r.errors[:photos]).to include("Must have between 1 and 5 photos")
      end

      it "allows up to 10 photos although the message says 5 (D-C53)" do
        r = build(:repository, owner: owner, title: "Many")
        9.times { r.photos.build(image: FilesTestHelper.png) }
        expect(r).to be_valid
        r.photos.build(image: FilesTestHelper.png)
        r.photos.build(image: FilesTestHelper.png)
        # WART(D-C53): limit is 10, message and comment say 5
        expect(r).not_to be_valid
      end

      it "rejects a non-image photo on create" do
        r = build(:repository, owner: owner, title: "Bad image")
        r.photos.destroy_all
        r.photos.build(image: FilesTestHelper.stl)
        expect(r).not_to be_valid
      end
    end

    it "private repositories need a password; public ones do not" do
      r = build(:repository, owner: owner, title: "P", share_type: "private")
      expect(r).not_to be_valid
      expect(r.errors[:password]).to include("Password is required for private projects")
      expect(build(:repository, owner: owner, title: "Q", password: nil)).to be_valid
    end

    it "share_type accepts only public/private (blank error message)" do
      r = build(:repository, owner: owner, share_type: "friends")
      expect(r).not_to be_valid
      expect(r.errors[:share_type]).to eq([""])
    end

    it "title is unique per owner, but the same title is fine for another owner" do
      expect(build(:repository, owner: owner, title: "Scope Check")).not_to be_valid
      expect(build(:repository, owner: create(:user), title: "Scope Check")).to be_valid
    end

    it "authenticate/pword compare against the bcrypt hash" do
      repo.update_columns(password: BCrypt::Password.create("pw"))
      expect(Repository.authenticate(repo.id, "pw")).to be(true)
      expect(Repository.authenticate(repo.id, "no")).to be(false)
    end

    it "authenticate keeps no class-level state shared between threads (review)" do
      repo.update_columns(password: BCrypt::Password.create("pw"))
      Repository.authenticate(repo.id, "pw")
      expect(Repository.instance_variable_get(:@repository)).to be_nil
    end

    it "authenticate raises on a soft-deleted repository (default_scope) and on a blank stored password" do
      expect { Repository.authenticate(repo.id, "x") }.to raise_error(BCrypt::Errors::InvalidHash)
      repo.update_columns(deleted: true)
      expect { Repository.authenticate(repo.id, "x") }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "fuzzy_search matches title or description by trigram similarity, best title first" do
      repo.update_columns(description: "a laser cutter lamp")
      other = create(:repository, owner: owner, title: "Unrelated Gadget", description: "zzz")
      found = Repository.fuzzy_search("scope chek")
      expect(found).to include(repo)
      expect(found).not_to include(other)
      expect(Repository.fuzzy_search("laser")).to include(repo)
    end

    it "thumbnail_variant returns the first photo's variant for variable images" do
      expect(repo.thumbnail_variant(:explore)).to be_a(ActiveStorage::VariantWithRecord)
      empty = Repository.new
      expect(empty.thumbnail_variant(:explore)).to be_nil
    end

    describe "zip cache" do
      it "zip_path is tmp/repository_zips/makerepo_<id>.zip and clear_zip_cache removes it after update and destroy" do
        FileUtils.mkdir_p(File.dirname(repo.zip_path))
        FileUtils.touch(repo.zip_path)
        repo.update!(description: "changed")
        expect(File.exist?(repo.zip_path)).to be(false)
        FileUtils.touch(repo.zip_path)
        repo.destroy
        expect(File.exist?(repo.zip_path)).to be(false)
      end

      it "a missing cache file is not an error" do
        expect { repo.clear_zip_cache }.not_to raise_error
      end
    end

    it "destroy lowers every member's reputation by 25 (can go negative) and removes dependents" do
      member = create(:user, reputation: 10)
      repo.users << member
      create(:comment, repository: repo)
      repo.destroy
      expect(member.reload.reputation).to eq(-15)
      expect(Comment.count).to eq(0)
    end

    it "to_csv serializes rows" do
      expect(Repository.to_csv([%w[a b], [1, 2]])).to eq("a,b\n1,2\n")
    end

    it "lists six license options" do
      expect(Repository.license_options.size).to eq(6)
    end

    it "youtube_link that is not a youtube URL is nulled on save" do
      repo.update!(youtube_link: "https://example.com/v")
      expect(repo.reload.youtube_link).to be_nil
    end
  end

  describe RepoFile do
    # FIXED(D-C06): the sniffed type and size are validated for every RepoFile; proficient projects keep the narrower list
    it "refuses an executable whatever it is attached to (proficient project, repository, proposal) (D-C06)" do
      pp = create(:proficient_project)
      exe = -> { content_named_upload("run.exe", type: "application/x-msdownload") }
      expect(RepoFile.new(file: exe.call, proficient_project: pp)).not_to be_valid
      expect(RepoFile.new(file: exe.call, repository: create(:repository, owner: owner))).not_to be_valid
      expect(RepoFile.new(file: exe.call, project_proposal: create(:project_proposal))).not_to be_valid
    end

    it "keeps the narrow list for proficient projects but the broad one for repositories" do
      pp = create(:proficient_project)
      zip = -> { content_named_upload("a.zip", content: "PK\x03\x04".b + ("\x00" * 40), type: "application/zip") }
      expect(RepoFile.new(file: zip.call, proficient_project: pp)).not_to be_valid
      expect(RepoFile.new(file: zip.call, repository: create(:repository, owner: owner))).to be_valid
    end

    it "does not re-check an unchanged older file when the record is saved again" do
      repo = create(:repository, owner: owner)
      legacy = RepoFile.new(repository: repo, file: content_named_upload("run.exe", type: "application/x-msdownload"))
      legacy.save!(validate: false)
      expect(legacy.reload.save).to be(true)
    end

    it "requires a file" do
      expect(RepoFile.new).not_to be_valid
    end

    it "touches the repository so the cached zip is invalidated" do
      repo = create(:repository, owner: owner)
      before = repo.reload.updated_at
      travel_to(1.minute.from_now) { create(:repo_file, repository: repo) }
      expect(repo.reload.updated_at).to be > before
    end
  end

  describe Photo do
    # FIXED(D-C54): the content-type validation runs on every save, not only on create
    it "validates the content type whenever the image is changed: swapping in a non-image on update is refused (D-C54)" do
      photo = create(:photo, :in_repository)
      photo.image.attach(FilesTestHelper.stl)
      expect(photo).not_to be_valid
      expect(photo.errors[:image]).to be_present
    end

    it "does not re-validate an unchanged legacy image: reordering a photo with an old webp/heic image still saves" do
      photo = create(:photo, :in_repository)
      photo.image.blob.update_columns(content_type: "image/heic")
      photo = Photo.find(photo.id)
      expect(photo.update(position: 7)).to be(true)
      expect(photo.reload.position).to eq(7)
    end

    it "does not re-validate when the form posts back the blob already attached (signed_id)" do
      photo = create(:photo, :in_repository)
      photo.image.blob.update_columns(content_type: "image/heic")
      photo = Photo.find(photo.id)
      expect(photo.update(image: photo.image.signed_id, position: 3)).to be(true)
    end

    it "refuses a swap to a different, already stored non-image blob given by signed_id" do
      photo = create(:photo, :in_repository)
      stl_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("solid x\nfacet normal 0 0 0\n"), filename: "a.stl", identify: false)
      expect(photo.update(image: stl_blob.signed_id)).to be(false)
      expect(photo.errors[:image]).to be_present
    end

    it "still accepts a valid image swap on update, and a clean re-save" do
      photo = create(:photo, :in_repository)
      expect(photo.save).to be(true)
      photo.image.attach(FilesTestHelper.png)
      expect(photo).to be_valid
    end

    it "requires an image" do
      expect(Photo.new).not_to be_valid
    end

    it "ordered scope sorts by position then creation" do
      repo = create(:repository, owner: owner)
      a = repo.photos.first
      a.update_columns(position: 5)
      b = create(:photo, repository: repo, position: 1)
      expect(repo.photos.reload.ordered.to_a).to eq([b, a])
    end

    it "defines the four named variants" do
      expect(Photo.new.image.attachment).to be_nil
      expect(Photo.reflect_on_attachment(:image).named_variants.keys)
        .to contain_exactly(:explore, :photo_slide, :photo_slide_first, :repo_display_wrapper)
    end

    it "touches its repository" do
      repo = create(:repository, owner: owner)
      before = repo.reload.updated_at
      travel_to(1.minute.from_now) { create(:photo, repository: repo) }
      expect(repo.reload.updated_at).to be > before
    end
  end

  describe Comment do
    it "caps content at 1000 characters" do
      c = create(:comment, content: "a" * 1000)
      expect(c).to be_valid
      c.content = "a" * 1001
      expect(c).not_to be_valid
    end

    it "does not validate the username column (any string, or nil)" do
      expect(create(:comment, username: nil)).to be_persisted
    end
  end

  describe Upvote do
    let(:comment) { create(:comment) }

    it "counts down for a downvote and flips by 2 on update" do
      up = Upvote.create!(user: owner, comment: comment, downvote: true)
      expect(comment.reload.upvote).to eq(-1)
      up.update!(downvote: false)
      expect(comment.reload.upvote).to eq(1)
    end

    it "does not validate that the comment exists (optional belongs_to, then the callback raises)" do
      expect { Upvote.create!(user: owner, comment_id: 0) }.to raise_error(NoMethodError)
    end
  end

  describe Like do
    it "counters follow create and destroy" do
      repo = create(:repository, owner: owner)
      like = Like.create!(user: create(:user), repository: repo)
      expect(repo.reload.like).to eq(1)
      like.destroy
      expect(repo.reload.like).to eq(0)
    end
  end

  describe ProficientProject do
    it "capitalizes the title on save (lower-casing the rest)" do
      expect(create(:proficient_project, title: "hELLO WORLD").title).to eq("Hello world")
    end

    it "title uniqueness is case-sensitive on the raw value, run before capitalize (D-C25)" do
      create(:proficient_project, title: "Widget")
      expect(build(:proficient_project, title: "widget")).to be_valid
      expect(build(:proficient_project, title: "Widget")).not_to be_valid
    end

    it "extract_valid_urls keeps only wiki.makerepo.com hosts and skips malformed urls" do
      pp = build(:proficient_project, description: "see https://wiki.makerepo.com/a https://evil.com/b https://x.wiki.makerepo.com/c https://notwiki.makerepo.com.evil.com/d")
      expect(pp.extract_valid_urls).to eq(%w[https://wiki.makerepo.com/a https://x.wiki.makerepo.com/c])
    end

    it "filter_by_attribute price is no longer a filter (the proficient column is gone): it returns the class unchanged" do
      expect(ProficientProject.filter_by_attribute("price", "Paid")).to eq(ProficientProject)
    end

    it "filter_by_attribute with an unknown attribute returns the class unchanged" do
      expect(ProficientProject.filter_by_attribute("zzz", "x")).to eq(ProficientProject)
    end

    it "training_status is the highest certification level the user holds for the training, defaulting to Beginner" do
      training = create(:training)
      user = create(:user)
      expect(ProficientProject.training_status(training.id, user.id)).to eq("Beginner")
    end

    it "deleting a project cascades to its requirements but leaves inverse requirements pointing at it dangling" do
      a = create(:proficient_project)
      b = create(:proficient_project)
      ProjectRequirement.create!(proficient_project: a, required_project: b)
      b.destroy
      expect(ProjectRequirement.where(required_project_id: b.id).count).to eq(1)
    end
  end

  describe ProjectProposal do
    it "slug: bare on create, '<id>.<slug>' on update" do
      pp = create(:project_proposal, title: "Smart Lamp!")
      expect(pp.slug).to eq("smart-lamp")
      pp.update!(description: "x")
      expect(pp.slug).to eq("#{pp.id}.smart-lamp")
    end

    it "requires username, title, email, client and a non-negative cost" do
      pp = ProjectProposal.new(project_cost: -1)
      expect(pp).not_to be_valid
      expect(pp.errors.attribute_names).to include(:username, :title, :email, :client, :project_cost)
    end

    it "does not validate email format" do
      expect(build(:project_proposal, email: "not-an-email")).to be_valid
    end

    it "has_user reflects a present user_id" do
      expect(build(:project_proposal, user: nil).has_user).to be(false)
      expect(create(:project_proposal).has_user).to be(true)
    end

    it "active_semester_label needs both season and year" do
      expect(build(:project_proposal, season: :fall, year: 2024).active_semester_label).to eq("Fall 2024")
      expect(build(:project_proposal, season: :fall).active_semester_label).to be_nil
    end

    it "by_semester orders newest year first, then season, nulls last" do
      a = create(:project_proposal, season: :fall, year: 2023)
      b = create(:project_proposal, season: :winter, year: 2024)
      c = create(:project_proposal, season: :fall, year: 2024)
      d = create(:project_proposal)
      expect(ProjectProposal.by_semester.to_a).to eq([c, b, a, d])
    end

    it "search matches title, client, username and description case-insensitively; blank returns everything" do
      match = create(:project_proposal, title: "Quantum Widget")
      miss = create(:project_proposal, title: "Boring Thing", client: "Zed", description: "plain", username: "nobody")
      expect(ProjectProposal.search("QUANTUM")).to include(match)
      expect(ProjectProposal.search("quantum")).not_to include(miss)
      expect(ProjectProposal.search("  ").to_a).to include(match, miss)
      expect(ProjectProposal.search(nil).to_a).to include(match, miss)
    end

    it "enum approved: nil is neither approved nor not_approved; the :approved scope matches 1 only" do
      pending_pp = create(:project_proposal)
      expect([pending_pp.approved?, pending_pp.not_approved?]).to eq([false, false])
      expect(ProjectProposal.approved).not_to include(pending_pp)
    end

    it "rejects numeric-string enum values by raising" do
      expect { ProjectProposal.new(approved: "1") }.to raise_error(ArgumentError)
      expect(ProjectProposal.new(approved: "approved").approved).to eq("approved")
    end

    it "destroy cascades to categories and joins but orphans linked repositories and revisions" do
      pp = create(:project_proposal, :completed)
      rev = create(:project_proposal, linked_project_proposal_id: pp.id)
      repo = pp.repositories.first
      pp.destroy
      expect(Repository.find(repo.id).project_proposal_id).to eq(pp.id)
      expect(rev.reload.linked_project_proposal_id).to eq(pp.id)
    end
  end

  describe ProjectKit do
    it "requires user and proficient_project_id (not existence)" do
      expect(ProjectKit.new).not_to be_valid
      expect(ProjectKit.new(user: owner, proficient_project_id: 0)).to be_valid
    end

    it "delivered defaults to falsey" do
      expect(create(:project_kit).delivered).to be_falsey
    end
  end

  describe ProjectRequirement do
    it "allows duplicates when proficient_project differs and rejects the same pair" do
      a, b, c = create_list(:proficient_project, 3)
      ProjectRequirement.create!(proficient_project: a, required_project: c)
      expect(ProjectRequirement.new(proficient_project: b, required_project: c)).to be_valid
      expect(ProjectRequirement.new(proficient_project: a, required_project: c)).not_to be_valid
    end
  end

  describe Video do
    it "accepts the four allow-listed video types and rejects others" do
      pp = create(:proficient_project)
      expect(build(:video, proficient_project: pp, video: [FilesTestHelper.mp4])).to be_valid
      expect(build(:video, proficient_project: pp, video: [FilesTestHelper.stl])).not_to be_valid
    end

    it "is valid with no file at all (validator only runs when attached)" do
      expect(Video.new).to be_valid
    end
  end
end
