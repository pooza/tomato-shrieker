# 🔴 **`source ack` を error にも効かせる (#1749)。**
#
# `error_acknowledged_at` はその確認で了解した error の時刻。期限の無い確認は「この時刻までに
# 終わった error の run」だけを了解する（次の定期実行がまた error なら赤）。
# `error_acknowledged_until` は期限つきの確認（`--until`）の期限。期限までは error でも緑、
# その間に成功したら、その時点で解除する。⚠ 期限の無い「ずっと緑」は作らない。
Sequel.migration do
  up do
    alter_table(:silence_ack) do
      add_column :error_acknowledged_at, :timestamp
      add_column :error_acknowledged_until, :timestamp
    end
  end

  down do
    alter_table(:silence_ack) do
      drop_column :error_acknowledged_at
      drop_column :error_acknowledged_until
    end
  end
end
