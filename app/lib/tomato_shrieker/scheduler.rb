module TomatoShrieker
  class Scheduler
    include Singleton
    include Package

    attr_reader :scheduler, :registry

    def exec
      register_all
      schedule_maintenance
      @scheduler.join
    rescue => e
      Sentry.capture_exception(e) if Sentry.initialized?
      logger.error(scheduler: {error: e})
    end

    # ソース定義を読み直し、**差分だけ**ジョブに反映する (#1459)。
    #
    # ⚠ **全件を貼り替えてはいけない。**`every` は登録時に発火しない代わりに
    # 次回発火が 1 周期先へずれるので、無変更のソースまで貼り替えると全ソースの
    # 位相がリセットされる。無変更なら**ジョブに触らない**。
    #
    # ⚠ **実行中の run は殺さない。**`unschedule` は以後の発火を止めるだけで、
    # 進行中の run は古い定義のまま完走する。これは仕様。
    #
    # ⚠ **スキーマ検証はしない。**起動時が検証していないのに reload だけ厳しいと
    # 「起動はできるのに reload は拒否される」定義が生まれる。検証は CLI の
    # `source edit` / `source validate` の担当。
    def reload
      @reload_mutex.synchronize do
        # 壊れた YAML があればここで raise する。#1530 以降 Config#load は読み切って
        # から 1 回で差し替えるので、**設定もジョブも何も変わらないまま**抜ける。
        Config.instance.reload
        apply(desired_sources)
      end
    end

    private

    def initialize
      @scheduler = Rufus::Scheduler.new
      # id => 設定の digest。無変更のソースを見分けるためだけに持つ。
      @registry = {}
      @reload_mutex = Mutex.new
    end

    def apply(desired)
      digests = desired.transform_values {|v| digest(v)}
      removed = @registry.keys - digests.keys
      stale = digests.reject {|id, d| @registry[id] == d}.keys
      added = stale - @registry.keys
      removed.each do |id|
        unschedule(id)
        @registry.delete(id)
      end
      stale.each do |id|
        unschedule(id)
        desired[id].each(&:register)
        @registry[id] = digests[id]
      end
      result = {added:, removed:, changed: stale - added}
      logger.info({scheduler: 'reload'}.merge(result))
      return result
    end

    def register_all
      desired = desired_sources
      in_threads = Parallel.processor_count * 2
      Parallel.each(desired.values.flatten, in_threads:, &:register)
      desired.each {|id, sources| @registry[id] = digest(sources)}
    end

    # 有効なソースを id 単位でまとめる。⚠ 1 つの定義が複数のソースクラスに
    # マッチしうる（`Source.all` はマッチしたクラスぶん yield する）ので、
    # 1 つの id が複数のインスタンスを持ちうる。
    def desired_sources
      return Source.all.reject(&:disable?).group_by(&:id)
    end

    # ⚠ **job id ではなく tag で消す。**`IcalendarSource#register` は remind と本体の
    # 2 本を同じ `tag: id` で登録し、戻り値は本体ぶんだけなので、job id を控える
    # 設計にすると remind ジョブが取り残される。
    def unschedule(id)
      @scheduler.jobs(tag: id).each(&:unschedule)
    end

    # ⚠ `class` は除く。同じ定義が複数クラスにマッチしても digest は 1 つ。
    def digest(sources)
      return Digest::SHA1.hexdigest(sources.first.to_h.except('class').to_json)
    end

    def schedule_maintenance
      retention = Config.instance['/monitor/retention_days']
      # ⚠ **無タグ**。reload は tag で消すので、この日次ジョブは巻き込まれない。
      @scheduler.every '1d', first_in: '1m' do
        count = SourceRunLog.prune(retention)
        logger.info(scheduler: 'maintenance', action: 'prune', retention_days: retention,
          deleted: count)
      rescue => e
        Sentry.capture_exception(e) if Sentry.initialized?
        logger.error(scheduler: 'maintenance', error: e)
      end
    end
  end
end
