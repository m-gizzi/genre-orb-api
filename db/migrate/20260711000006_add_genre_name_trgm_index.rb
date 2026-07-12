# frozen_string_literal: true

class AddGenreNameTrgmIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :genres, :name,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_genres_on_name_trgm",
              algorithm: :concurrently
  end
end
