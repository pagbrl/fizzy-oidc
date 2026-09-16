module Fizzy
  module Oidc
    class Provisioner
      def initialize(claims)
        @claims = claims
        @config = Fizzy::Oidc.config
      end

      def call
        ActiveRecord::Base.transaction do
          identity = find_or_create_identity
          account  = find_or_bootstrap_account(identity)
          user     = find_or_create_user(account, identity)

          reconcile_role(user)
          reconcile_accesses(account, user)

          [identity, user, account]
        end
      end

      private
        attr_reader :claims, :config

        def find_or_create_identity
          identity = Identity.find_by(oidc_subject: claims.subject, oidc_provider: config.provider_name)
          identity ||= Identity.find_by(email_address: claims.email)
          identity ||= Identity.new

          identity.assign_attributes(
            email_address: claims.email,
            oidc_subject: claims.subject,
            oidc_provider: config.provider_name
          )
          identity.save!
          identity
        end

        def find_or_bootstrap_account(identity)
          return Account.first if Account.any?

          Account.create_with_owner(
            account: { name: config.account_name },
            owner:   { name: claims.name, identity: identity }
          )
        end

        def find_or_create_user(account, identity)
          user = account.users.find_by(identity: identity)
          return refresh_user(user) if user

          if account.users.owner.none?
            account.users.create!(identity: identity, name: claims.name, role: :owner, verified_at: Time.current)
          else
            account.users.create!(identity: identity, name: claims.name, role: :member, verified_at: Time.current)
          end
        end

        def refresh_user(user)
          user.update!(name: claims.name) if user.name.blank? || user.name == user.identity.email_address
          user.verify unless user.verified?
          user.update!(active: true) unless user.active?
          user
        end

        def reconcile_role(user)
          return if user.owner?

          desired = admin_group_member? ? :admin : :member
          user.update!(role: desired) unless user.role.to_sym == desired
        end

        def admin_group_member?
          config.admin_group.present? && claims.groups.include?(config.admin_group)
        end

        def reconcile_accesses(account, user)
          desired_names = (config.default_boards + config.group_boards(claims.groups)).uniq
          desired_boards = account.boards.where(name: desired_names).to_a

          missing = desired_names - desired_boards.map(&:name)
          Rails.logger.warn("[fizzy-oidc] mapped boards not found: #{missing.inspect}") if missing.any?

          desired_boards.each do |board|
            Access.find_or_create_by!(user: user, board: board, account: account)
          end

          managed_names = (config.default_boards + config.all_group_boards).uniq
          stale = user.accesses
            .joins(:board)
            .where(boards: { name: managed_names, all_access: false })
            .where.not(boards: { id: desired_boards.map(&:id) })
          stale.destroy_all
        end
    end
  end
end
