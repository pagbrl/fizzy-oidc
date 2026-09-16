require "yaml"
require "singleton"

module Fizzy
  module Oidc
    class Config
      include Singleton

      def issuer            = ENV.fetch("FIZZY_OIDC_ISSUER")
      def client_id         = ENV.fetch("FIZZY_OIDC_CLIENT_ID")
      def client_secret     = ENV.fetch("FIZZY_OIDC_CLIENT_SECRET")
      def redirect_uri      = ENV.fetch("FIZZY_OIDC_REDIRECT_URI", nil)
      def scopes            = ENV.fetch("FIZZY_OIDC_SCOPES", "openid email profile groups").split
      def groups_claim      = ENV.fetch("FIZZY_OIDC_GROUPS_CLAIM", "groups")
      def provider_name     = ENV.fetch("FIZZY_OIDC_PROVIDER_NAME", "oidc")

      def account_name      = mapping.dig("account", "name") || ENV.fetch("FIZZY_OIDC_ACCOUNT_NAME", "Fizzy")

      def admin_group       = mapping.dig("mappings", "admin_group")
      def default_boards    = Array(mapping.dig("mappings", "default_boards"))

      def group_boards(group_names)
        boards = group_names.flat_map { |name| Array(groups_mapping.dig(name, "boards")) }
        boards.uniq
      end

      def all_group_boards
        groups_mapping.values.flat_map { |g| Array(g["boards"]) }.uniq
      end

      def groups_mapping
        mapping.dig("mappings", "groups") || {}
      end

      def reload!
        @mapping = nil
      end

      private
        def mapping
          @mapping ||= load_mapping
        end

        def load_mapping
          path = ENV.fetch("FIZZY_OIDC_MAPPING_PATH", default_mapping_path)
          return {} unless File.exist?(path)
          YAML.safe_load_file(path, permitted_classes: [Symbol]) || {}
        end

        def default_mapping_path
          Rails.root.join("config", "fizzy_oidc.yml").to_s
        end
    end
  end
end
