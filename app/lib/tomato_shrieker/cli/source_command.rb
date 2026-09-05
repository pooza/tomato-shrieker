# frozen_string_literal: true

require 'shellwords'

module TomatoShrieker
  class SourceCommand < Thor
    include Package

    desc 'list', 'ソース一覧 (id とクラス名) を表示'
    def list
      Source.all do |source|
        puts [source.id, source.class.name.split('::').last].join("\t")
      end
    end

    desc 'fetch ID', 'ソースのサマリーを表示'
    def fetch(id)
      source = find_source!(id)
      raise Thor::Error, "source does not support fetch: #{id}" unless source.respond_to?(:summary)
      puts source.summary.deep_stringify_keys.to_yaml
    end

    desc 'shriek ID', 'ソースを実行（投稿）'
    def shriek(id)
      source = find_source!(id)
      source.exec
    end

    desc 'touch ID', 'ソースをタッチ'
    def touch(id)
      source = find_source!(id, FeedSource)
      source.touch
    end

    desc 'clear ID', 'ソースのレコードをすべて削除'
    def clear(id)
      source = find_source!(id, FeedSource)
      source.clear
    end

    desc 'add ID', '雛形を生成し $EDITOR で編集してソース定義を作成'
    method_option :class, type: :string, default: 'feed',
      desc: "ソース種別 (#{SourceTemplates::ALL.keys.join('/')})"
    def add(id)
      raise Thor::Error, "invalid id: #{id}" unless id.match?(/\A[\w.-]+\z/)
      path = new_source_path(id)
      raise Thor::Error, "source already exists: #{id}" if File.exist?(path)
      template = SourceTemplates::ALL[options[:class]]
      unless template
        raise Thor::Error, "unknown class: #{options[:class]} (#{SourceTemplates::ALL.keys.join('/')})"
      end
      File.write(path, template.to_yaml)
      edit_and_validate(id, path)
    end

    desc 'edit ID', '$EDITOR でソース定義を開き、保存後に検証'
    def edit(id)
      edit_and_validate(id, existing_source_path!(id))
    end

    desc 'delete ID', 'ソース定義ファイルを削除（確認付き）'
    def delete(id)
      path = existing_source_path!(id)
      return unless yes?("delete #{path} ? [y/N]")
      File.delete(path)
      say "deleted: #{path}"
      say reload_hint
    end

    desc 'disable ID', 'ソースを停止 (disable: true)'
    def disable(id)
      set_disable(id, true)
    end

    desc 'enable ID', 'ソースを再開 (disable を解除)'
    def enable(id)
      set_disable(id, false)
    end

    desc 'ack ID', '出ている警告を確認済みにする（サイレント不発 / 未達）'
    # 🔴 **出力は実際に効いた範囲だけを言う (#1506)。**
    #
    # ⚠ 以前は `SilenceAck` を書くだけで **`undelivered` には一切効かない**のに、
    # 出力は「確認済みにしました」とだけ返していた。**運用者は緑に戻ると期待して
    # Kuma の赤を放置する。**いまは ack が両方に効くが、**どちらに効いたかを言う**。
    def ack(id)
      source = find_source!(id)
      undelivered = source.undelivered?
      tolerance = source.monitor_silence_tolerance_seconds
      return say(nothing_to_ack_message(id)) unless undelivered || tolerance
      SilenceAck.acknowledge(id)
      say "#{id} を確認済みにしました。"
      # ⚠ 「今後も問題ない」の保証ではないことを操作のたびに示す。
      say '  未達 (undelivered) を解除しました。この後の試行で届かなければ、また警告します。' if undelivered
      say "  次に silence_tolerance (#{tolerance_label(source)}) を超えたら、再び警告します。" if tolerance
    end

    desc 'reload', '稼働中の scheduler にソース定義を読み直させる (SIGHUP)'
    def reload
      daemon = SchedulerDaemon.new
      case daemon.alive_state
      when :alive
        pid = daemon.pid
        Process.kill('HUP', pid)
        say "reload requested (pid #{pid})"
        # ⚠ シグナルは非同期なので、CLI は「要求した」までしか言えない (#1529)。
        say '  結果はログの {"scheduler":"reload",...} 行で確認できます。'
      when :unknown
        # ⚠ :unknown（EPERM）を :dead と混ぜない。プロセスは生きている可能性がある。
        raise Thor::Error, "PID #{daemon.pid} exists but is not ours. reload できません。"
      else
        say 'scheduler は停止しています。ソース定義は次回起動時に読み込まれます。'
      end
    end

    desc 'validate [ID]', 'ソース定義を JSON Schema で検証（ID 省略時は全件）'
    def validate(id = nil)
      paths = id ? [existing_source_path!(id)] : source_paths
      ng = 0
      paths.each do |path|
        params = YAML.load_file(path)
        errors = SourceValidator.validate(params)
        if errors.empty?
          # WARN はスキーマ上は妥当な定義への指摘なので ng には数えない (#1470)。
          warnings = SourceValidator.warnings(params)
          say "#{warnings.empty? ? 'OK' : 'WARN'}\t#{source_id(path)}"
          warnings.each {|v| say "    - #{v}"}
        else
          ng += 1
          say "NG\t#{source_id(path)}"
          errors.each {|e| say "    - #{e}"}
        end
      rescue Psych::SyntaxError => e
        ng += 1
        say "NG\t#{source_id(path)}"
        say "    - YAML 構文エラー: #{e.message}"
      end
      raise Thor::Error, "#{ng} source(s) invalid" if ng.positive?
    end

    private

    def nothing_to_ack_message(id)
      return "#{id} は silence_tolerance が未設定で、未達の警告も出ていません。確認するものがありません。"
    end

    # silence_tolerance を人が読める長さで返す (#1513)。
    #
    # ⚠ **整数除算で「0日」と出してはいけない。** スキーマは `12h` / `30m` を許す
    # ので（`^((\d+(\.\d+)?[smhdwMy])+|\d+(\.\d+)?)$`）、日未満を設定した
    # ソースでは「次に silence_tolerance (0日) を超えたら」と出ていた。
    # ⚠ #1496 の「9 月上旬に 7d → 3d へ締める」運用で日未満を入れたら踏む。
    def tolerance_label(source)
      seconds = source.monitor_silence_tolerance_seconds
      return "#{seconds / 86_400}日" if (seconds % 86_400).zero?
      return "#{seconds / 3_600}時間" if (seconds % 3_600).zero?
      return "#{seconds / 60}分" if (seconds % 60).zero?
      return "#{seconds}秒"
    end

    def find_source!(id, klass = nil)
      sources = klass ? klass.all : Source.all
      source = sources.find {|v| v.id == id}
      raise Thor::Error, "source not found: #{id}" unless source
      return source
    end

    def edit_and_validate(id, path)
      open_editor(path)
      errors = SourceValidator.validate(YAML.load_file(path))
      if errors.empty?
        say "OK: #{path}"
        say reload_hint
      else
        warn "WARNING: #{id} の定義にスキーマ違反があります:"
        errors.each {|e| warn "    - #{e}"}
      end
    rescue Psych::SyntaxError => e
      warn "WARNING: #{id} の定義が YAML として不正です: #{e.message}"
    end

    def open_editor(path)
      editor = ENV['EDITOR'].presence || ENV['VISUAL'].presence || 'vi'
      warn "WARNING: エディタの起動に失敗しました: #{editor}" unless system(*Shellwords.split(editor), path)
    end

    # コメントやキー順を保つため YAML ラウンドトリップではなく行単位で操作する。
    # トップレベル（インデントなし）の `disable:` 行のみを対象にする。
    # 既存の `disable:` 行（true/false 問わず）を一旦すべて除去してから付け直すことで、
    # `disable: false` 明記済みのソースに対する二重キー（YAML 後勝ちで停止が効かない）を防ぐ。
    def set_disable(id, value)
      path = existing_source_path!(id)
      lines = File.readlines(path)
      removed = lines.reject! {|v| v.match?(/\Adisable\s*:\s*(true|false)\b/)}
      if value
        lines.insert(lines.first&.start_with?('---') ? 1 : 0, "disable: true\n")
      elsif removed.nil?
        say "already enabled: #{id}"
        return
      end
      File.write(path, lines.join)
      say "#{value ? 'disabled' : 'enabled'}: #{id}"
      say reload_hint
    end

    # ⚠ **自動 reload はしない (#1459)。**add / edit / delete / disable / enable の
    # 契約を 1 つずつのままに保つ。自動にすると「エディタを閉じただけで本番へ反映
    # される」「validate NG のとき」「daemon が停止中のとき」の分岐を全部説明する
    # ことになる。代わりに、反映がまだであることを操作のたびに言う。
    def reload_hint
      return '⚠ 稼働中の scheduler に反映するには bin/shrieker source reload'
    end

    def sources_dir
      File.join(Environment.dir, 'config/sources')
    end

    def new_source_path(id)
      File.join(sources_dir, "#{id}.yaml")
    end

    def existing_source_path!(id)
      path = source_paths.find {|v| source_id(v) == id}
      raise Thor::Error, "source not found: #{id}" unless path
      return path
    end

    def source_paths
      Dir.glob(File.join(sources_dir, '*.{yaml,yml}'))
    end

    def source_id(path)
      File.basename(path).sub(/\.ya?ml\z/, '')
    end
  end
end
