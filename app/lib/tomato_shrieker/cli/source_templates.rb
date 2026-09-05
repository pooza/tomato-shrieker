# frozen_string_literal: true

module TomatoShrieker
  # `bin/shrieker source add --class` が生成する雛形 (#1429)。
  # ⚠ SourceCommand から切り出しただけ。ここに振る舞いは置かない。
  module SourceTemplates
    # `add --class` で生成する雛形の共通パーツ。
    DEFAULT_DEST = {
      'hooks' => ['https://mastodon.example.com/mulukhiya/webhook/CHANGE_ME'],
      'tags' => [],
    }.freeze
    DEFAULT_SCHEDULE = {'cron' => '0 0 * * *'}.freeze

    # `add --class` で生成する種別ごとの雛形。いずれもスキーマ妥当な最小構成。
    ALL = {
      'feed' => {
        'source' => {'feed' => 'https://example.com/feed'},
        'dest' => DEFAULT_DEST,
      },
      'url' => {
        'source' => {'url' => 'https://example.com/'},
        'dest' => DEFAULT_DEST,
      },
      'news' => {
        'source' => {'news' => {'phrase' => 'CHANGE_ME'}},
        'dest' => DEFAULT_DEST,
      },
      'github' => {
        'source' => {'github' => {'repository' => 'owner/repo', 'timeline' => 'releases'}},
        'dest' => DEFAULT_DEST,
      },
      'icalendar' => {
        'source' => {'ical' => 'https://example.com/calendar.ics'},
        'schedule' => DEFAULT_SCHEDULE,
        'dest' => DEFAULT_DEST,
      },
      'youtube' => {
        'source' => {'youtube' => {'channel' => {'url' => 'https://www.youtube.com/@CHANGE_ME'}}},
        'dest' => DEFAULT_DEST,
      },
      'command' => {
        'source' => {'command' => ['echo', 'hello'], 'dir' => '/path/to/workdir'},
        'schedule' => DEFAULT_SCHEDULE,
        'dest' => DEFAULT_DEST,
      },
      'text' => {
        'source' => {'text' => 'CHANGE_ME'},
        'schedule' => DEFAULT_SCHEDULE,
        'dest' => DEFAULT_DEST,
      },
    }.freeze
  end
end
