# 🔴 **どの段で落ちた run かを run_log 自身に書く (#1586)。**
#
# ⚠⚠ これまでは `shrieker_errors` が空であることを「エントリを 1 件も読めていない
# 失敗（＝取得段）」の**代理**に使っていた。代理が成立するのは FeedSource だけで、
# CommandSource / IcalendarSource は `create_template` で落ちると
# `shrieker_errors` が空のまま error 行になるため、**エントリ処理段の失敗が
# 「取得段の失敗」と誤読され、緩めたしきい値がそのまま残っていた**。
#
# ⚠ 既存行は NULL。`entry_level_error?` は NULL の行だけ従来の代理へフォールバック
# するので、デプロイ直後に健全なソースが一斉 503 になることはない。
Sequel.migration do
  change do
    alter_table(:source_run_log) do
      add_column :entry_stage, TrueClass
    end
  end
end
