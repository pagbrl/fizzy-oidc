module Fizzy
  module Oidc
    class UsersController < ApplicationController
      before_action :ensure_admin

      def create
        user, created = Precreator.new(Current.account, email: params.require(:email_address), name: params[:name]).call

        render status: created ? :created : :ok, json: {
          id: user.id,
          name: user.name,
          role: user.role,
          active: user.active,
          email_address: user.identity.email_address
        }
      rescue ProvisioningError, ActiveRecord::RecordInvalid => error
        render status: :unprocessable_entity, json: { error: error.message }
      end
    end
  end
end
