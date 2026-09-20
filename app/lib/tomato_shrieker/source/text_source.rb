module TomatoShrieker
  class TextSource < Source
    # ⚠ **エントリ処理段 (#1586) は立てない。**本文は設定に書かれた固定文字列で、
    # 落ちても失うものが無い（次の run が同じものを流す）。
    def exec
      shriek(template: create_template, visibility:)
    end

    def create_template(type = :default, status = nil)
      template = super
      template[:status] ||= text
      return template
    end

    def text
      return self['/source/text']
    end

    def self.all(&block)
      return enum_for(__method__) unless block
      Source.all.grep(self).each(&block)
    end
  end
end
