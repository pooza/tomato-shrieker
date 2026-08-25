module TomatoShrieker
  class Template < Ginseng::Template
    include Package

    # Source#templates は Template をインスタンスに memo 化するので、複製しないと
    # Parallel.each の各スレッドが同じ params を上書きし合う (#1474)。
    # @erb / @path は読み取り専用なので共有したままでよい。
    #
    # ⚠ **@params の複製は 1 段（浅コピー）** (#1490)。`Ginseng::Template#[]=` が
    # `value.is_a?(Hash) ? value.deep_symbolize_keys : value` で**スロットごと
    # 差し替える**前提に乗っている。⚠ **Hash 以外の可変値（Array 等）を params に
    # 入れると共有に戻る**ので、そのときは別途複製が要る。
    def initialize_copy(original)
      super
      @params = original.params.dup
    end

    def source
      return params[:source] || params[:feed]
    end

    alias feed source

    def entry
      return params[:entry]
    end
  end
end
