class CreateOidcProjectGroups < ActiveRecord::Migration[8.0]
  def up
    Fizzy::Oidc::Schema.ensure!(connection)
  end

  def down
    %i[ oidc_group_grants oidc_board_groups oidc_group_memberships oidc_groups ].each { drop_table it, if_exists: true }
  end
end
