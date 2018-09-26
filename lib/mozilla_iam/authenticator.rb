module MozillaIAM

  class Authenticator < Auth::OAuth2Authenticator

    def enabled?
      true
    end

    def after_authenticate(auth_token)
      begin
        id_token = auth_token[:credentials][:id_token]
        payload, header =
          JWT.decode(
            id_token,
            aud: SiteSetting.auth0_client_id
          )

        logout_delay = payload['exp'].to_i - payload['iat'].to_i
        ::PluginStore.set('mozilla-iam', 'logout_delay', logout_delay)
        Rails.cache.write('mozilla-iam/logout_delay', logout_delay)

        auth_token[:session][:mozilla_iam] = {
          last_refresh: Time.now
        }

        result = Auth::Result.new

        result.email = email = payload['email']
        result.email_valid = email_valid = payload['email_verified']
        result.user = user = User.find_by_email(email) if email_valid
        if Array(user&.secondary_emails).include? email
          raise SecondaryEmailError.new(user, email)
        end
        result.name = payload['name']
        uid = payload['sub']
        result.extra_data = { uid: uid }

        if user
          Profile.new(user, uid).force_refresh
        end

        result
      rescue => e
        result = Auth::Result.new
        result.failed = true
        if e.class == SecondaryEmailError
          result.failed_reason = I18n.t("mozilla_iam.authenticator.secondary_email_error",
            secondary_email: e.email,
            primary_email: e.user.email,
            idp: e.idp
          )
        else
          result.failed_reason = I18n.t("login.omniauth_error_unknown")
        end
        Rails.logger.error("#{e.class} (#{e.message})\n#{e.backtrace.join("\n")}")
        return result
      end
    end

    def after_create_account(user, auth)
      uid = auth[:extra_data][:uid]
      Profile.new(user, uid).force_refresh
    end

    def register_middleware(omniauth)
      omniauth.provider(
        :auth0,
        SiteSetting.auth0_client_id,
        SiteSetting.auth0_client_secret,
        SiteSetting.auth0_domain,
        {
          authorize_params: {
            action: "signup",
            scope: 'openid name email'
          }
        }
      )
    end

    class SecondaryEmailError < StandardError
      attr_reader :user
      attr_reader :email

      def initialize(user, email)
        @user = user
        @email = email
        super "user #{user.id} attempted to log in with secondary email #{email}"
      end

      def idp
        @idp ||= Profile.for(user)&.idp || "Unknown"
      end
    end
  end
end
