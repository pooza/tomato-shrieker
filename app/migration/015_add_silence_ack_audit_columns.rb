# 🔴 **確認が「どの run の何を」了解したのかを残す (#1680)。**`acknowledged_at` の 1 つだけだと、
# 数週間後に「なぜ緑なのか」を再構成できない。
#
# ⚠ `silence_acknowledged_at` は沈黙の起点に使う時刻。未達・取りこぼしだけを確認した ack では
# 動かさないので、`acknowledged_at` とは別に持つ。既存の行は、これまでどおり両方に効いていたものとして写す。
Sequel.migration do
  up do
    alter_table(:silence_ack) do
      add_column :silence_acknowledged_at, :timestamp
      add_column :acknowledged_run_id, Integer
      add_column :acknowledged_reasons, :text
    end
    from(:silence_ack).update(silence_acknowledged_at: Sequel[:acknowledged_at])
  end

  down do
    alter_table(:silence_ack) do
      drop_column :silence_acknowledged_at
      drop_column :acknowledged_run_id
      drop_column :acknowledged_reasons
    end
  end
end
