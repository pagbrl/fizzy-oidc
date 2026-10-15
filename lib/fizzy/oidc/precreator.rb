module Fizzy
  module Oidc
    # Creates a member before their first login, so an outside system can grant
    # them boards right away. The Provisioner finds the identity by email on that
    # first login and links it to the OIDC subject.
    class Precreator
      def initialize(account, email:, name:)
        @account = account
        @email = email.to_s.strip.downcase
        @name = name.to_s.strip.presence || @email
      end

      def call
        raise ProvisioningError, "email is required" if email.empty?

        ActiveRecord::Base.transaction do
          identity = Identity.find_or_create_by!(email_address: email)
          user = account.users.find_by(identity: identity)
          next [user, false] if user

          [account.users.create!(identity: identity, name: name, role: :member, verified_at: Time.current), true]
        end
      end

      private
        attr_reader :account, :email, :name
    end
  end
end
