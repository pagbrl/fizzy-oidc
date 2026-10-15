class AddOidcColumnsToIdentities < ActiveRecord::Migration[8.0]
  def up
    Fizzy::Oidc::Schema.ensure!(connection)
  end

  def down
    remove_index :identities, [:oidc_provider, :oidc_subject], if_exists: true
    remove_column :identities, :oidc_provider, if_exists: true
    remove_column :identities, :oidc_subject, if_exists: true
  end
end
