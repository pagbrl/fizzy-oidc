module Fizzy
  module Oidc
    # The two OIDC columns on `identities`, added if missing.
    #
    # A migration alone is not enough: on a fresh database `db:prepare` loads
    # Fizzy's schema and marks every migration older than its version as run.
    # Once Fizzy's schema is newer than the gem's migration — true since the pin
    # moved to 3068c2a7 — a new install never gets the columns. The engine runs
    # this after db:prepare, db:migrate and db:schema:load instead.
    module Schema
      def self.ensure!(connection = ActiveRecord::Base.connection)
        return unless connection.table_exists?(:identities)

        connection.add_column :identities, :oidc_subject, :string unless connection.column_exists?(:identities, :oidc_subject)
        connection.add_column :identities, :oidc_provider, :string unless connection.column_exists?(:identities, :oidc_provider)
        unless connection.index_exists?(:identities, [:oidc_provider, :oidc_subject])
          connection.add_index :identities, [:oidc_provider, :oidc_subject], unique: true
        end
      end
    end
  end
end
