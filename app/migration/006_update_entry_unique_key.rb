Sequel.migration do
  change do
    alter_table(:entry) do
      drop_index :feed, name: :entry_feed_title_summary_url_index
      add_index [:feed, :url, :published], unique: true
    end
  end
end
