$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "active_record"
require "logger"
require "pathname"
require "fileutils"
require "yaml"
require "ostruct"

module Rails
  def self.logger
    @logger ||= Logger.new(IO::NULL)
  end

  def self.root
    @root ||= begin
      path = Pathname.new(File.expand_path("../tmp/test-root", __dir__))
      FileUtils.mkdir_p(path)
      path
    end
  end

  def self.error
    @error ||= Object.new.tap do |o|
      def o.report(*) end
    end
  end
end

ActiveRecord::Base.logger = Logger.new(IO::NULL)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  create_table :identities do |t|
    t.string :email_address
    t.string :oidc_subject
    t.string :oidc_provider
    t.timestamps
  end
  add_index :identities, [:oidc_provider, :oidc_subject], unique: true

  create_table :accounts do |t|
    t.string :name, null: false
    t.timestamps
  end

  create_table :users do |t|
    t.integer :account_id
    t.integer :identity_id
    t.string :name
    t.string :role, default: "member"
    t.boolean :active, default: true
    t.datetime :verified_at
    t.timestamps
  end

  create_table :boards do |t|
    t.integer :account_id
    t.integer :creator_id
    t.string :name
    t.boolean :all_access, default: false
    t.timestamps
  end

  create_table :accesses do |t|
    t.integer :user_id
    t.integer :board_id
    t.integer :account_id
    t.string :involvement, default: "access_only"
    t.timestamps
  end
end

class Identity < ActiveRecord::Base
  has_many :users, dependent: :nullify
end

class Account < ActiveRecord::Base
  has_many :users, dependent: :destroy
  has_many :boards, dependent: :destroy

  def self.create_with_owner(account:, owner:)
    create!(**account).tap do |a|
      a.users.create!(role: "system", name: "System", active: true)
      a.users.create!(**owner.merge(role: "owner", verified_at: Time.current, active: true) { |_, v, _| v })
    end
  end
end

class User < ActiveRecord::Base
  belongs_to :account
  belongs_to :identity, optional: true
  has_many :accesses, dependent: :destroy
  has_many :boards, through: :accesses

  enum :role, %w[ owner admin member system ].index_by(&:itself), scopes: false

  scope :owner, -> { where(active: true, role: :owner) }

  def admin?
    super || owner?
  end

  def verified?
    verified_at.present?
  end

  def verify
    update!(verified_at: Time.current) unless verified?
  end
end

class Board < ActiveRecord::Base
  belongs_to :account
  has_many :accesses, dependent: :destroy
end

class Access < ActiveRecord::Base
  belongs_to :user
  belongs_to :board
  belongs_to :account
end

require "fizzy/oidc/version"
require "fizzy/oidc/config"
require "fizzy/oidc/claims"
require "fizzy/oidc/provisioner"

module Fizzy::Oidc
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ProvisioningError < Error; end

  def self.config
    Config.instance
  end
end

module TestHelpers
  def reset_db
    [Access, Board, User, Account, Identity].each(&:delete_all)
  end

  def reset_config
    Fizzy::Oidc.config.reload!
  end

  def write_mapping(contents)
    path = Rails.root.join("fizzy_oidc.yml")
    File.write(path, contents)
    ENV["FIZZY_OIDC_MAPPING_PATH"] = path.to_s
    reset_config
    path
  end

  def clear_mapping
    ENV.delete("FIZZY_OIDC_MAPPING_PATH")
    reset_config
  end

  def build_auth(sub:, email:, name: nil, groups: [], groups_claim: "groups")
    OpenStruct.new(
      uid: sub,
      info: OpenStruct.new(email: email, name: name),
      extra: OpenStruct.new(raw_info: { "sub" => sub, "email" => email, "name" => name, groups_claim => groups })
    )
  end
end

class Minitest::Test
  include TestHelpers

  def setup
    reset_db
    clear_mapping
    ENV["FIZZY_OIDC_ISSUER"]        = "https://id.test"
    ENV["FIZZY_OIDC_CLIENT_ID"]     = "client"
    ENV["FIZZY_OIDC_CLIENT_SECRET"] = "secret"
    ENV["FIZZY_OIDC_PROVIDER_NAME"] = "oidc"
  end
end
