module TomatoShrieker
  class SourceCollisionsTest < TestCase
    SOURCE_ID = '__test_source_collisions__'.freeze
    OTHER_ID = '__test_source_collisions_other__'.freeze

    def setup
      cleanup
      @base = Time.at(Time.now.to_i - 600)
    end

    def teardown
      cleanup
      super
    end

    def cleanup
      SourceRunLog.where(source_id: [SOURCE_ID, OTHER_ID]).delete
    end

    # #1561: 同じ秒に発火したソースの群を、同じ顔ぶれごとに数える
    def test_find
      [0, 300].each do |offset|
        create_run(SOURCE_ID, @base + offset + 0.1)
        create_run(OTHER_ID, @base + offset + 0.7)
      end
      create_run(SOURCE_ID, @base + 120) # 相手のいない run は数えない
      group = find_group

      assert_equal([SOURCE_ID, OTHER_ID], group[:source_ids])
      assert_equal(2, group[:count])
    end

    # 同じソースが同じ秒に 2 本走っても「衝突」ではない
    def test_find_ignores_same_source
      create_run(SOURCE_ID, @base + 0.1)
      create_run(SOURCE_ID, @base + 0.7)

      assert_nil(find_group)
    end

    # 窓の外の run は数えない
    def test_find_ignores_old_runs
      create_run(SOURCE_ID, @base - 7200)
      create_run(OTHER_ID, @base - 7200)

      assert_nil(find_group)
    end

    private

    def find_group
      return SourceCollisions.find(hours: 1).find {|v| v[:source_ids].include?(SOURCE_ID)}
    end

    def create_run(source_id, at)
      SourceRunLog.create(source_id:, executed_at: at, status: SourceRunLog::STATUS_SUCCESS,
        duration_ms: 100, attempted_count: 0, delivered_count: 0)
    end
  end
end
