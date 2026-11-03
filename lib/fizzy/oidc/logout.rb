module Fizzy
  module Oidc
    # Where to send the browser once Fizzy's session is gone: the IdP's
    # end_session_endpoint, or the SSO session stays open and the IdP signs the
    # member straight back in on their next click.
    module Logout
      # client_id lets the IdP accept post_logout_redirect_uri without an ID
      # token, for sessions opened before Fizzy kept one: the member is then
      # asked to confirm on the IdP's side.
      def self.url(id_token:, post_logout_redirect_uri:)
        endpoint = Fizzy::Oidc.config.end_session_endpoint or return
        params = { client_id: Fizzy::Oidc.config.client_id, id_token_hint: id_token, post_logout_redirect_uri: }.compact
        "#{endpoint}?#{URI.encode_www_form(params)}"
      rescue => error
        Rails.logger.warn("[fizzy-oidc] signing out of Fizzy only, no IdP logout: #{error.message}")
        nil
      end
    end
  end
end
