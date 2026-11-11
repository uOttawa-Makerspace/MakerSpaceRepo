# frozen_string_literal: true

require "rails_helper"

# Revoking an awarded project badge from the admin screen also deactivates the certification the
# approval granted (a soft demotion: the row stays), and approving the item again restores it.
RSpec.describe "Revoking a project badge", type: :request do
  include ContentSpecHelpers

  let(:training) { create(:training, skill: create(:skill, name: "Technical")) }
  let(:project) { create(:proficient_project, training: training) }
  let(:buyer) { create(:user, :volunteer_with_dev_program) }

  def item_with(status)
    create(:order_item, order: create(:order, :completed, user_id: buyer.id), proficient_project: project, status: status)
  end

  let(:item) { item_with("Waiting for approval") }
  let(:certifications) { Certification.unscoped.where(user_id: buyer.id) }

  def approve(order_item)
    post approve_project_proficient_projects_path, params: { oi_id: order_item.id, order_item: { admin_comments: "ok" } }
  end

  def revoke(order_item)
    post order_item_revoke_path(order_item)
  end

  context "as an admin, after the item was approved" do
    let!(:admin) { content_sign_in_as(:admin) }
    let(:cert) { certifications.first }

    before { approve(item) }

    it "marks the item revoked and deactivates its certification, keeping the row and the session" do
      expect(cert).to be_active
      expect { revoke(item) }.not_to change { [certifications.count, ProficientProjectSession.count] }
      expect(response).to redirect_to(admin_index_path)
      expect(flash[:notice]).to eq("The badge has been revoked.")
      expect(item.reload.status).to eq("Revoked")
      cert.reload
      expect(cert.active).to be(false)
      expect(cert.demotion_reason).to eq(OrderItem::REVOKED_BADGE_REASON)
      expect(cert.demotion_staff).to eq(admin)
      expect(buyer.certifications).to be_empty
    end

    it "is safe to run twice" do
      revoke(item)
      expect { revoke(item) }.not_to change { cert.reload.attributes }
      expect(item.reload.status).to eq("Revoked")
      expect(certifications.count).to eq(1)
    end

    it "restores the certification when the item is approved again, and a second approval changes nothing" do
      revoke(item)
      approve(item)
      expect(item.reload.status).to eq("Awarded")
      expect(cert.reload).to be_active
      expect(cert.demotion_reason).to be_nil
      expect(cert.demotion_staff).to be_nil
      expect { approve(item) }.not_to change { [certifications.count, ProficientProjectSession.count] }
      expect(flash[:error]).to include("no longer waiting")
    end

    it "does not reactivate a certification an admin demoted by hand; approving grants a new one" do
      revoke(item)
      cert.update!(demotion_reason: "manual")
      approve(item)
      expect(item.reload.status).to eq("Awarded")
      expect(cert.reload).not_to be_active
      expect(certifications.where(active: true).count).to eq(1)
    end

    it "tells the admin when the certification cannot be saved, and revokes nothing" do
      cert.update_column(:level, "Bogus")
      revoke(item)
      expect(response).to redirect_to(admin_index_path)
      expect(flash[:alert]).to start_with("The badge could not be revoked:")
      expect(item.reload.status).to eq("Awarded")
      expect(cert.reload).to be_active
    end
  end

  context "with two items for the same user and project" do
    before { content_sign_in_as(:admin) }

    it "keeps the badge while another awarded item backs it, then deactivates it with the last revoke" do
      other = item_with("Waiting for approval")
      approve(item)
      approve(other)
      revoke(item)
      expect(buyer.certifications.count).to eq(1)
      revoke(other)
      expect(buyer.certifications).to be_empty
      expect(certifications.count).to eq(1)
    end

    it "reactivates exactly one certification when a second item is approved after the first was revoked" do
      approve(item)
      revoke(item)
      second = item_with("Revoked")
      approve(second)
      expect(second.reload.status).to eq("Awarded")
      expect(certifications.count).to eq(1)
      expect(certifications.first).to be_active
      expect(ProficientProjectSession.count).to eq(2)
    end
  end

  it "refuses a staff member who is not an admin and changes nothing" do
    content_sign_in_as(:staff)
    awarded = item_with("Awarded")
    revoke(awarded)
    expect(response).to have_http_status(:forbidden)
    expect(awarded.reload.status).to eq("Awarded")
  end

  it "does not touch another certification when a never-approved submission is revoked" do
    content_sign_in_as(:admin)
    other_cert = create(:certification, user: buyer)
    expect { revoke(item) }.not_to change { certifications.count }
    expect(item.reload.status).to eq("Revoked")
    expect(other_cert.reload).to be_active
  end
end
