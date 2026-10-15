module TomatoShrieker
  class CommandSource < Source
    include CommandRunner

    def exec
      # 🔴 **`run_command` を抜けた先はエントリ処理段 (#1586)。**⚠⚠ コマンドの出力は日付に
      # 依存するものがあり（dqdai-anniv 等）、落ちたぶんは**次の run で取り返せない**。
      # ⚠ コマンドが非 0 で終わるまでは取得段なので段を立てない。
      statuses = run_command.split(delimiter).map(&:strip).select(&:present?)
      @delivery_stats&.enter_entry_stage! if statuses.present?
      statuses.each do |status|
        template = create_template(:default, status)
        shriek(template:, visibility:)
      end
    end

    def delimiter
      return Regexp.new("#{self['/source/delimiter'] || '====='}\n?")
    end

    def register
      prepare_command
      return super
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.grep(self).each(&block)
    end
  end
end
