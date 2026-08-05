module TomatoShrieker
  class Template < Ginseng::Template
    include Package

    # Source#templates は Template をインスタンスに memo 化するので、複製しないと
    # Parallel.each の各スレッドが同じ params を上書きし合う (#1474)。
    # @erb / @path は読み取り専用なので共有したままでよい。
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
