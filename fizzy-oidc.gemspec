require_relative "lib/fizzy/oidc/version"

Gem::Specification.new do |spec|
  spec.name        = "fizzy-oidc"
  spec.version     = Fizzy::Oidc::VERSION
  spec.authors     = ["Paul Gabriel"]
  spec.summary     = "OIDC single sign-on for Fizzy, with group-to-board provisioning."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir[
    "{app,config,db,lib}/**/*",
    "LICENSE",
    "README.md"
  ]

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "omniauth", "~> 2.1"
  spec.add_dependency "omniauth_openid_connect", "~> 0.8"

  spec.add_development_dependency "minitest", "~> 5.20"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "sqlite3", ">= 2.0"
end
