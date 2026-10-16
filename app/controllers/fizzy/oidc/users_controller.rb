module Fizzy
  module Oidc
    class UsersController < ApplicationController
      before_action :ensure_admin

      def create
        user, created = Precreator.new(Current.account, email: params.require(:email_address), name: params[:name]).call

        render status: created ? :created : :ok, json: user_json(user)
      rescue ProvisioningError, ActiveRecord::RecordInvalid => error
        render status: :unprocessable_entity, json: { error: error.message }
      end

      # Fizzy's own API lets a user change only their own address, behind a
      # confirmation mail. The IdP has already proven the new one, so the
      # outside system rewrites the identity's address directly.
      def update
        user = Current.account.users.find(params[:id])
        if user.identity.nil?
          render status: :unprocessable_entity, json: { error: "user has no identity" } and return
        end

        user.identity.update!(email_address: params.require(:email_address))
        render json: user_json(user)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
        render status: :unprocessable_entity, json: { error: error.message }
      end

      private
        def user_json(user)
          {
            id: user.id,
            name: user.name,
            role: user.role,
            active: user.active,
            email_address: user.identity&.email_address
          }
        end
    end
  end
end
