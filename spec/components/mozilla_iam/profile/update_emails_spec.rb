require_relative '../../../iam_helper'

describe MozillaIAM::Profile do
  describe described_class.refresh_methods do
    it { should include(:update_emails) }
  end

  let(:email) { "one@email.com" }
  let(:secondary_emails) { ["two@email.com", "three@email.com"] }
  let(:user) { user = Fabricate(:user_single_email, email: email) }
  let(:profile) { MozillaIAM::Profile.new(user, "uid") }

  def mock_profile_emails(*secondary)
    profile.stubs(:attr).with(:secondary_emails).returns(secondary)
  end

  before do
    secondary_emails.each do |email|
      Fabricate(:secondary_email, user: user, email: email)
    end
    mock_profile_emails(*secondary_emails)
  end

  describe "#store_taken_email_or_raise" do
    let(:taken_emails) { [] }
    before do
      u = Fabricate(:user, email: "taken_primary@email.com")
      Fabricate(:secondary_email, user: u, email: "taken_secondary@email.com")
    end

    it "stores email if secondary email is taken as a primary email" do
      begin
        Fabricate(:secondary_email, user: user, email: "taken_primary@email.com")
      rescue Exception => e
        profile.send(:store_taken_email_or_raise, e, taken_emails)
        expect(taken_emails).to contain_exactly("taken_primary@email.com")
      end
    end

    it "stores email if secondary email is taken as secondary email" do
      begin
        Fabricate(:secondary_email, user: user, email: "taken_secondary@email.com")
      rescue Exception => e
        profile.send(:store_taken_email_or_raise, e, taken_emails)
        expect(taken_emails).to contain_exactly("taken_secondary@email.com")
      end
    end

    it "raises exception if it's not because of a taken email" do
      begin
        Fabricate(:user_email, user: user, email: "second_primary@email.com")
      rescue Exception => e
        expect { profile.send(:store_taken_email_or_raise, e, taken_emails) }.to raise_exception e
        expect(taken_emails).to eq []
      end
    end
  end

  describe "#update_emails" do
    shared_examples "leaves primary" do
      it "leaves primary email alone" do
        profile.send(:update_emails)
        expect(user.email).to eq email
      end
    end

    include_examples "leaves primary"

    it "leaves secondary emails alone" do
      profile.send(:update_emails)
      expect(user.secondary_emails).to match_array secondary_emails
    end

    context "when profile has no secondary emails" do
      before { mock_profile_emails() }

      include_examples "leaves primary"

      it "removes seconary emails" do
        profile.send(:update_emails)
        expect(user.secondary_emails).to eq []
      end
    end

    context "when profile has different secondary emails" do
      before { mock_profile_emails("two@email.com", "four@email.com") }

      include_examples "leaves primary"

      it "updates secondary emails" do
        profile.send(:update_emails)
        expect(user.secondary_emails).to contain_exactly("two@email.com", "four@email.com")
      end

      context "and some of those emails are taken" do
        before do
          u = Fabricate(:user, email: "taken1@email.com")
          Fabricate(:secondary_email, user: u, email: "taken2@email.com")
          mock_profile_emails("taken1@email.com", "two@email.com", "taken2@email.com", "four@email.com")
        end

        include_examples "leaves primary"

        it "stores taken emails, and updates the rest" do
          profile.send(:update_emails)
          expect(profile.send(:get, :taken_emails)).to contain_exactly("taken1@email.com", "taken2@email.com")
          expect(user.secondary_emails).to contain_exactly("two@email.com", "four@email.com")
        end
      end
    end

    context "when primary email is in profile secondary emails" do
      before { mock_profile_emails("two@email.com", "one@email.com", "four@email.com") }

      include_examples "leaves primary"

      it "sets remaining secondary emails" do
        profile.send(:update_emails)
        expect(user.secondary_emails).to contain_exactly("two@email.com", "four@email.com")
      end
    end
  end
end

describe MozillaIAM::Profile, type: :request do
  describe "#update_emails" do
    context "with a non english locale set" do
      it "shouldn't fail" do
        SiteSetting.allow_user_locale = true
        user = Fabricate(:user, locale: :es)
        authenticate_user(user)
        sign_in(user)

        Fabricate(:user, email: "taken@email.com")
        described_class.any_instance.stubs(:attr).with(:secondary_emails).returns(["taken@email.com"])
        described_class.stubs(:refresh_methods).returns([:update_emails])
        user.custom_fields["mozilla_iam_last_refresh"] = Time.now - 1.day
        user.save_custom_fields

        get "/"
        expect(response.status).to eq 200
        expect(I18n.locale).to eq :es
      end
    end
  end
end
