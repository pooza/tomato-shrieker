Sequel.migration do
  change do
    create_table :source_run_log do
      primary_key :id
      text :source_id, null: false
      timestamp :executed_at, null: false
      text :status, null: false
      text :error_message
      integer :duration_ms
      index :executed_at
      index [:source_id, :executed_at]
    end
  end
end
