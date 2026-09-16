module Fizzy
  module Oidc
    class Claims
      attr_reader :subject, :email, :name, :groups

      def self.from_omniauth(auth)
        info     = auth.info || {}
        extra    = auth.extra&.raw_info || {}
        subject  = auth.uid.presence || extra["sub"]
        email    = info.email.presence || extra["email"]
        name     = info.name.presence  || extra["name"] || email
        groups   = Array(extra[Fizzy::Oidc.config.groups_claim])

        new(subject:, email:, name:, groups:)
      end

      def initialize(subject:, email:, name:, groups: [])
        raise ProvisioningError, "OIDC claim 'sub' is required" if subject.blank?
        raise ProvisioningError, "OIDC claim 'email' is required" if email.blank?

        @subject = subject
        @email   = email.to_s.strip.downcase
        @name    = name.to_s.strip.presence || @email
        @groups  = groups.map(&:to_s)
      end
    end
  end
end
