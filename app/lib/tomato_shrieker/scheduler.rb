module TomatoShrieker
  class Scheduler
    include Singleton
    include Package

    attr_reader :scheduler, :registry

    def exec
      # ⚠ 初回登録も reload と**同じ差分適用**を通す (#1545 Codex P1)。SIGHUP は
      # 起動の途中から受け付けるので、両方が素通しで register すると同じソースに
      # ジョブが 2 本立ち、以後 digest が一致するので誰も気付けない。
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
        apply(desired_sources, action: 'reload')
      end
    end

    private

    def initialize
      @scheduler = Rufus::Scheduler.new
      # id => 設定の digest。無変更のソースを見分けるためだけに持つ。
      @registry = {}
      @reload_mutex = Mutex.new
    end

    def apply(desired, action:)
      digests = desired.transform_values {|v| digest(v)}
      removed = drop_removed(digests.keys)
      stale = digests.reject {|id, d| @registry[id] == d}.keys
      added = stale - @registry.keys
      failed = swap_all(stale, desired)
      # ⚠ **失敗した id は registry を更新しない。**次の reload で必ずやり直す。
      (stale - failed).each {|id| @registry[id] = digests[id]}
      result = {added: added - failed, removed:, changed: stale - added - failed, failed:}
      logger.info({scheduler: action}.merge(result))
      return result
    end

    def drop_removed(wanted)
      removed = @registry.keys - wanted
      removed.each do |id|
        unschedule(id)
        @registry.delete(id)
      end
      return removed
    end

    # 失敗した id を返す。⚠ CommandSource#register は bundle install を走らせる
    # ので、初回登録の速さのために並列のまま置く。
    def swap_all(stale, desired)
      in_threads = Parallel.processor_count * 2
      return Parallel.map(stale, in_threads:) {|id| id unless swap(id, desired[id])}.compact
    end

    # 🔴 **新しいジョブを立ててから古いジョブを落とす (#1545 Codex P1)。**
    # `register` は失敗しうる（`CommandSource` は bundle install を走らせるし、
    # reload はスキーマ検証をしないので不正な cron 式もここへ来る）。先に消すと、
    # **失敗したソースが次の reload までジョブ 1 本無いまま放置される**。
    def swap(id, sources)
      old = @scheduler.jobs(tag: id)
      sources.each(&:register)
      old.each(&:unschedule)
      return true
    rescue => e
      # 立った分だけ巻き戻して、古いジョブをそのまま残す。
      unschedule(id, except: old)
      Sentry.capture_exception(e, tags: {source: id}) if Sentry.initialized?
      logger.error(scheduler: 'reload', source: id, error: e)
      return false
    end

    def register_all
      @reload_mutex.synchronize {apply(desired_sources, action: 'register')}
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
    def unschedule(id, except: [])
      kept = except.map(&:job_id)
      @scheduler.jobs(tag: id).reject {|v| kept.include?(v.job_id)}.each(&:unschedule)
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
