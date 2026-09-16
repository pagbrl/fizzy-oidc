class AddOidcColumnsToIdentities < ActiveRecord::Migration[8.0]
  def change
    change_table :identities do |t|
      t.string :oidc_subject
      t.string :oidc_provider
    end

    add_index :identities, [:oidc_provider, :oidc_subject], unique: true
  end
end
