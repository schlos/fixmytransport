class AddDataGenerationColumnsToOperators < ActiveRecord::Migration
  def self.up
    add_column :operators, :generation_low, :integer
    add_column :operators, :generation_high, :integer
    add_column :operators, :previous_id, :integer
    remove_index :operators, :cached_slug
    add_index :operators, [:cached_slug, :generation_low, :generation_high]
  end

  def self.down
    remove_column :operators, :generation_low, :integer
    remove_column :operators, :generation_high, :integer
    remove_column :operators, :previous_id, :integer
    remove_index :operators, [:cached_slug, :generation_low, :generation_high]
    add_index :operators, :cached_slug
  end
end