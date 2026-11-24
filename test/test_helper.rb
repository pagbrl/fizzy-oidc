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

  create_table :sessions do |t|
    t.integer :identity_id
    t.text :oidc_id_token
    t.timestamps
  end

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

  create_table :cards do |t|
    t.integer :board_id
    t.integer :creator_id
    t.timestamps
  end

  create_table :assignments do |t|
    t.integer :card_id
    t.integer :assignee_id
    t.timestamps
  end

  create_table :closures do |t|
    t.integer :card_id
    t.integer :user_id
    t.timestamps
  end

  create_table :events do |t|
    t.integer :board_id
    t.integer :creator_id
    t.string :action
    t.timestamps
  end
end

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
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
  scope :active, -> { where(active: true, role: %i[ owner admin member ]) }
  scope :alphabetically, -> { order("lower(name)") }

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
  has_many :users, through: :accesses
end

class Access < ActiveRecord::Base
  belongs_to :user
  belongs_to :board
  belongs_to :account
end

class Card < ActiveRecord::Base
  belongs_to :board
  belongs_to :creator, class_name: "User"
end

class Assignment < ActiveRecord::Base
  belongs_to :card, touch: true
  belongs_to :assignee, class_name: "User"
end

class Closure < ActiveRecord::Base
  belongs_to :card, touch: true
  belongs_to :user
end

class Event < ActiveRecord::Base
  belongs_to :board
  belongs_to :creator, class_name: "User"
end

class User::DayTimeline
  TIMELINEABLE_ACTIONS = %w[ card_published comment_created ]
end

require "fizzy/oidc/version"
require "fizzy/oidc/config"
require "fizzy/oidc/claims"
require "fizzy/oidc/provisioner"
require "fizzy/oidc/precreator"
require "fizzy/oidc/schema"
require "fizzy/oidc/logout"
require "fizzy/oidc/people"
require "fizzy/oidc/project_groups"
require "fizzy/oidc/patches/access"
require "fizzy/oidc/patches/board"
require "fizzy/oidc/patches/user"
%w[ group group_membership board_group group_grant ].each { require_relative "../app/models/fizzy/oidc/#{it}" }

Fizzy::Oidc::Schema.ensure!
Access.include(Fizzy::Oidc::Patches::Access)
Board.include(Fizzy::Oidc::Patches::Board)
User.include(Fizzy::Oidc::Patches::User)

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
    [Event, Closure, Assignment, Card, Access, Board, User, Account, Identity,
     Fizzy::Oidc::GroupGrant, Fizzy::Oidc::BoardGroup, Fizzy::Oidc::GroupMembership, Fizzy::Oidc::Group].each(&:delete_all)
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
