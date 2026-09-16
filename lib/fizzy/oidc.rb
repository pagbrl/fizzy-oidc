require "fizzy/oidc/version"
require "fizzy/oidc/engine"

module Fizzy
  module Oidc
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class ProvisioningError < Error; end

    def self.config
      Config.instance
    end
  end
end

require "fizzy/oidc/config"
require "fizzy/oidc/claims"
require "fizzy/oidc/provisioner"
