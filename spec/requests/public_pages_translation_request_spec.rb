# frozen_string_literal: true

require "rails_helper"

# Logged-out pages read from the locale files: the English page keeps its wording and the same
# page under ?locale=fr is in French. Text is compared with whitespace collapsed, as a browser
# shows it.
RSpec.describe "Public pages in English and French", type: :request do
  def freedom = "Share — copy and redistribute the material in any medium or format."
  def adapt = "Adapt — remix, transform, and build upon the material for any purpose, even commercially."
  def revoke = "The licensor cannot revoke these freedoms as long as you follow the license terms."
  def attribution = "Attribution — You must give appropriate credit, provide a link to the license, and indicate if changes were made. You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use."
  def non_commercial = "Non-Commercial — You may not use the material for commercial purposes."
  def share_alike = "ShareAlike — If you remix, transform, or build upon the material, you must distribute your contributions under the same license as the original."
  def no_derivatives = "If you remix, transform, or build upon the material, you may not distribute the modified material."
  def restrictions = "No additional restrictions — You may not apply legal terms or technological measures that legally restrict others from doing anything the license permits."

  def sidebar_en
    [
      "Licenses", "Common Create - Attribution", "Common Create - Attribution - Share Alike",
      "Common Create - Attribution - No Derivatives", "Common Create - Attribution - Non-Commerical",
      "Attribution - Non-Commerical - Share Alike", "Attribution - Non-Commerical - No Derivatives"
    ]
  end

  def sidebar_fr
    [
      "Licences", "Creative Commons - Attribution", "Creative Commons - Attribution - Partage dans les mêmes conditions",
      "Creative Commons - Attribution - Pas de modification", "Creative Commons - Attribution - Pas d'utilisation commerciale",
      "Attribution - Pas d'utilisation commerciale - Partage dans les mêmes conditions",
      "Attribution - Pas d'utilisation commerciale - Pas de modification"
    ]
  end

  def french_common
    [
      "Vous êtes autorisé à :", "Selon les conditions suivantes :",
      "Partager — copier, distribuer et communiquer le matériel par tous moyens et sous tous formats.",
      "L'offrant ne peut pas retirer ces autorisations tant que vous respectez les termes de la licence.",
      "Attribution — Vous devez créditer l'œuvre", "Licence officielle",
      "Pas de restrictions complémentaires — Vous n'êtes pas autorisé à appliquer des conditions légales"
    ]
  end

  # helper => [English title, English terms, a French term]
  def license_pages
    {
      licenses_cca_path: ["Common Creative - Attribution", [freedom, adapt, attribution], "Attribution — Vous devez"],
      licenses_ccasa_path: ["Common Creative - Attribution - Share Alike", [freedom, adapt, share_alike], "Partage dans les mêmes conditions — Si vous remixez"],
      licenses_ccand_path: ["Common Creative - Attribution - No Derivatives", ["No-Derivatives — #{no_derivatives}", freedom], "Pas de modification — Si vous remixez"],
      licenses_ccanc_path: ["Common Creative - Attribution - Non-Commercial", [non_commercial, adapt], "Pas d'utilisation commerciale — Vous n'êtes pas autorisé"],
      licenses_ancsa_path: ["Attribution - Non-commercial - Share Alike", [non_commercial, share_alike, adapt], "Partage dans les mêmes conditions — Si vous remixez"],
      licenses_ancnd_path: ["Attribution - Non-Commercial - No Derivatives", ["No Derivatives — #{no_derivatives}", non_commercial], "Pas de modification — Si vous remixez"]
    }
  end

  def page_text
    Nokogiri::HTML(response.body).at_css("body").text.gsub(/[[:space:]]+/, " ")
  end

  def visit(path, locale)
    get path, params: {locale: locale}
    expect(response).to have_http_status(:ok)
    page_text
  end

  %i[licenses_cca_path licenses_ccasa_path licenses_ccand_path licenses_ccanc_path licenses_ancsa_path licenses_ancnd_path].each do |helper|
    describe helper.to_s do
      it "keeps its English wording" do
        title, en_terms, = license_pages.fetch(helper)
        text = visit(public_send(helper), "en")
        expect(text).to include(title, "You are free to:", "Under the following terms:", revoke, restrictions, "Formal License")
        expect(text).to include(*en_terms, *sidebar_en)
        expect(response.body).to include("<title>License | MakerRepo</title>")
      end

      it "is in French" do
        fr_term = license_pages.fetch(helper).last
        text = visit(public_send(helper), "fr")
        expect(text).to include(*french_common, fr_term, *sidebar_fr)
        expect(text).not_to include("You are free to", "Formal License")
        expect(response.body).to include("<title>Licence | MakerRepo</title>")
      end

      it "links to the formal licence text" do
        get public_send(helper)
        expect(response.body).to match(%r{href="http://creativecommons\.org/licenses/by[a-z-]*/3\.0/legalcode"})
      end
    end
  end

  describe "getting started" do
    it "keeps the account page's English wording" do
      text = visit(getting_started_sua_path, "en")
      expect(text).to include(
        "Setting Up An Account",
        "If you don't have an MakerRepo account yet, just head on over to makerepo.com/new or click the Sign Up button on the home page.",
        "Create a short, memorable repository name. All of your own repository names must be unique and must not contain special characters with the exception of a hyphen. For example, \"hello-world\".",
        "Enter in a valid email address. For example, \"johndoe@example.com\".",
        "Enter in your password. Your password must contain: 10 characters, 5 unique characters, and not be a commonly used password.",
        "Signing up and creating an MakerRepo account is totally free! After you sign up, please be sure to complete your profile and link your MakerRepo account to your Github account.",
        "Help Center / Getting Started", "Setting up an account", "Creating a repository",
        "If any error occurs, or if you would like to make a suggestion, do not hesitate to contact us."
      )
      expect(response.body).to include("<title>Getting Started | MakerRepo</title>")
      expect(response.body).to include(%(href="#{new_user_path}">makerepo.com/new</a>), %(href="#{root_path}">home page</a>))
    end

    it "keeps the repository page's English wording" do
      text = visit(getting_started_cr_path, "en")
      expect(text).to include(
        "Creating A Repository",
        "In the upper-right corner of any page, click the Create button.",
        "Create a short, memorable repository name. All of your repository names must be unique and must not contain special characters with the exception of a hyphen. For example, \"hello-world\".",
        "Optionally, submit a description of your repository.",
        "Optionally, create a github repository or link to an existing repository. You must have your account linked to github to have this option.",
        "Optionally, add files. Files are stored inside of your github repository.",
        "Submit photos of your projects. A minimum of one photo must be submitted.",
        "Select a category that best fits your repository.",
        "Optionally, add tags.",
        "Select a license, there are five different license that may be chosen from. For example, the Creative Common - Attribution license."
      )
    end

    it "is in French" do
      text = visit(getting_started_sua_path, "fr")
      expect(text).to include("Créer un compte", "Centre d'Aide / Pour commencer", "Créer un dépôt", "nous contacter", "page d'accueil", "lier votre compte MakerRepo à votre compte GitHub")
      expect(text).not_to include("Setting Up An Account", "contact us")
      text = visit(getting_started_cr_path, "fr")
      expect(text).to include("Créer un dépôt", "Si vous le souhaitez, ajoutez des étiquettes.", "lié votre compte à GitHub", "licence Creative Commons - Attribution")
      expect(text).not_to include("Optionally")
      expect(response.body).to include("<title>Pour commencer | MakerRepo</title>")
    end
  end

  describe "about and contact" do
    it "keeps the English wording" do
      text = visit(about_path, "en")
      expect(text).to include(
        "About Us", "The Centre for Entrepreneurship and Engineering Design (CEED)",
        "CEED offers you engineering design and entrepreneurship education and experience that includes:",
        "Giving you opportunities throughout your studies to design, build and test products that meet customer needs",
        "Developing your business acumen by introducing you to essential business concepts and exposing you to industry",
        "Discovering a better client approach, one that allows the public to discover products and validate the design",
        "Building your sales and communication skills",
        "Offering you experiential learning opportunities with industry in the areas of design and prototyping services and commercialization of technologies"
      )
      expect(response.body).to include("<title>About | MakerRepo</title>")

      create(:contact_info, name: "Lab One", show_hours: true)
      text = visit(contact_path, "en")
      expect(text).to include("Contact Us", "Follow Us", "Lab One", "@uOCEED", "@uoceed", "CEED")
      expect(response.body).to include("<title>Contact | MakerRepo</title>")
    end

    it "is in French" do
      text = visit(about_path, "fr")
      expect(text).to include("À propos de nous", "Le Centre d'entrepreneuriat et de conception technique (CEED)", "Le renforcement de vos compétences en vente et en communication")
      expect(text).not_to include("About Us", "Building your sales")
      expect(response.body).to include("<title>À propos | MakerRepo</title>")

      text = visit(contact_path, "fr")
      expect(text).to include("Contactez-nous", "Suivez-nous")
      expect(text).not_to include("Follow Us")
    end
  end

  describe "links from emails" do
    let(:user) { create(:user, :regular_user) }
    let(:confirm_path) { confirm_users_path(token: user.generate_token_for(:email_confirmation)) }
    let(:unlock_path) { unlock_account_users_path(token: user.generate_token_for(:account_unlock)) }
    let(:resend_path) { resend_confirmation_users_path(user: {email: "who@example.test"}) }

    it "keeps the English wording of the confirm page" do
      text = visit(confirm_path, "en")
      expect(text).to include("Confirm your email address", "Press the button to confirm your email address and finish setting up your account.", "Nothing changes until you press the button.", "Confirm my email", "Cancel")
      expect(response.body).to include("<title>Confirm your email | MakerRepo</title>")
    end

    it "keeps the English wording of the unlock page" do
      text = visit(unlock_path, "en")
      expect(text).to include("Unlock your account", "Press the button to unlock your account so you can sign in again.", "Nothing changes until you press the button.", "Unlock my account", "Cancel")
      expect(response.body).to include("<title>Unlock your account | MakerRepo</title>")
    end

    it "keeps the English wording of the resend page" do
      text = visit(resend_path, "en")
      expect(text).to include("Resend the confirmation email", "Send a new confirmation email to who@example.test?", "Nothing is sent until you press the button.", "Send the email", "Cancel")
      expect(response.body).to include("<title>Resend confirmation email | MakerRepo</title>")
    end

    it "is in French" do
      text = visit(confirm_path, "fr")
      expect(text).to include("Confirmez votre adresse courriel", "Confirmer mon courriel", "Annuler", "Rien ne change tant que vous n'appuyez pas sur le bouton.")
      expect(text).not_to include("Cancel")
      text = visit(unlock_path, "fr")
      expect(text).to include("Déverrouillez votre compte", "Déverrouiller mon compte", "Annuler")
      text = visit(resend_path, "fr")
      expect(text).to include("Renvoyer le courriel de confirmation", "Envoyer un nouveau courriel de confirmation à who@example.test?", "Rien n'est envoyé tant que vous n'appuyez pas sur le bouton.", "Envoyer le courriel")
    end
  end
end
