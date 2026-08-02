module TomatoShrieker
  class DeliveryStatsTest < TestCase
    def setup
      @stats = DeliveryStats.new
      @shrieker = MastodonShrieker.allocate
    end

    def test_initial
      assert_equal(0, @stats.attempted_count)
      assert_equal(0, @stats.delivered_count)
      assert_equal({}, @stats.shrieker_errors)
      assert_equal(0, @stats.error_count)
      assert_nil(@stats.first_error)
      assert_false(@stats.error?)
      assert_true(@stats.noop?)
    end

    def test_record_success
      @stats.record_success(@shrieker)
      @stats.record_success(@shrieker)

      assert_equal(2, @stats.attempted_count)
      assert_equal(2, @stats.delivered_count)
      assert_false(@stats.error?)
      assert_false(@stats.noop?)
    end

    def test_record_error
      @stats.record_error(@shrieker, RuntimeError.new('first'))
      @stats.record_error(@shrieker, RuntimeError.new('second'))

      assert_equal(2, @stats.attempted_count)
      assert_equal(0, @stats.delivered_count)
      assert_equal({'TomatoShrieker::MastodonShrieker' => 2}, @stats.shrieker_errors)
      assert_equal(2, @stats.error_count)
      assert_equal('first', @stats.first_error.message)
      assert_true(@stats.error?)
      assert_false(@stats.noop?)
    end

    def test_shrieker_errors_isolated
      @stats.record_error(@shrieker, RuntimeError.new('boom'))
      errors = @stats.shrieker_errors
      errors['TomatoShrieker::MastodonShrieker'] = 999

      assert_equal({'TomatoShrieker::MastodonShrieker' => 1}, @stats.shrieker_errors)
    end

    def test_thread_safety
      threads = Array.new(8) do
        Thread.new do
          25.times {@stats.record_success(@shrieker)}
        end
      end
      threads.each(&:join)

      assert_equal(200, @stats.attempted_count)
      assert_equal(200, @stats.delivered_count)
    end
  end
end
