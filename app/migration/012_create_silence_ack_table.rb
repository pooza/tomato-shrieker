Sequel.migration do
  change do
    create_table :silence_ack do
      primary_key :id
      text :source_id, null: false
      timestamp :acknowledged_at, null: false
      index :source_id, unique: true
    end
  end
end
