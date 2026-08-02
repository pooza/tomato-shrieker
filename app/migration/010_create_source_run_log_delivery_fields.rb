Sequel.migration do
  change do
    alter_table :source_run_log do
      add_column :attempted_count, Integer, null: false, default: 0
      add_column :delivered_count, Integer, null: false, default: 0
      add_column :shrieker_errors, String, text: true
      add_index [:source_id, :delivered_count, :executed_at]
    end
  end
end
