module Fizzy
  module Oidc
    # The OIDC columns on `identities` and `sessions`, added if missing.
    #
    # A migration alone is not enough: on a fresh database `db:prepare` loads
    # Fizzy's schema and marks every migration older than its version as run.
    # Once Fizzy's schema is newer than the gem's migration — true since the pin
    # moved to 3068c2a7 — a new install never gets the columns. The engine runs
    # this after db:prepare, db:migrate and db:schema:load instead.
    #
    # The project group tables are the gem's own, created the same way. Their
    # keys take the type of Fizzy's: UUIDs there, integers in the test stubs.
    module Schema
      def self.ensure!(connection = ActiveRecord::Base.connection)
        return unless connection.table_exists?(:identities)

        connection.add_column :identities, :oidc_subject, :string unless connection.column_exists?(:identities, :oidc_subject)
        connection.add_column :identities, :oidc_provider, :string unless connection.column_exists?(:identities, :oidc_provider)
        unless connection.index_exists?(:identities, [:oidc_provider, :oidc_subject])
          connection.add_index :identities, [:oidc_provider, :oidc_subject], unique: true
        end

        if connection.table_exists?(:sessions) && !connection.column_exists?(:sessions, :oidc_id_token)
          connection.add_column :sessions, :oidc_id_token, :text
        end

        create_project_group_tables(connection) if connection.table_exists?(:users) && connection.table_exists?(:boards)
      end

      def self.create_project_group_tables(connection)
        key = connection.columns(:users).find { it.name == "id" }.type

        create_table(connection, :oidc_groups, key) do |t|
          t.column :account_id, key, null: false
          t.string :name, null: false
          t.timestamps
          t.index [:account_id, :name], unique: true
        end
        create_table(connection, :oidc_group_memberships, key) do |t|
          t.column :group_id, key, null: false
          t.column :user_id, key, null: false, index: true
          t.timestamps
          t.index [:group_id, :user_id], unique: true
        end
        create_table(connection, :oidc_board_groups, key) do |t|
          t.column :board_id, key, null: false
          t.column :group_id, key, null: false, index: true
          t.timestamps
          t.index [:board_id, :group_id], unique: true
        end
        # The accesses an attached group created, and only those: an access
        # someone had before stays theirs and no group takes it back.
        create_table(connection, :oidc_group_grants, key) do |t|
          t.column :board_id, key, null: false
          t.column :user_id, key, null: false, index: true
          t.timestamps
          t.index [:board_id, :user_id], unique: true
        end
      end

      def self.create_table(connection, name, key, &)
        connection.create_table(name, id: key, &) unless connection.table_exists?(name)
      end
    end
  end
end
