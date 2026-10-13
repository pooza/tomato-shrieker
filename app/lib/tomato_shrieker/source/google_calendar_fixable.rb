module TomatoShrieker
  # Google カレンダー由来の予定の癖を直す。`IcalendarSource` から切り出した (#1691)。
  module GoogleCalendarFixable
    def google?
      return self['/source/google'] unless self['/source/google'].nil?
      # ⚠ コマンド由来のソースは `uri` が nil (#1691)。
      return false unless uri
      return uri.host.split('.').member?('google')
    end

    def fix_google_calendar_entry(data)
      # Google Calendarで、終日予定の終了日が1日ずれる。
      data[:end_date] -= 1.days if data[:all_day] && (data[:start_date] < data[:end_date])

      # Google Meet
      lines = data[:body].split(/\r?\n/)
      lines.reject! {|line| line.match?(/^Google Meet に参加:/)}
      lines.reject! {|line| line.match?(/^Meet の詳細:/)}
      data[:body] = lines.join("\n").strip

      # 場所
      data[:location] = data[:location].split(',').first
      return data
    end
  end
end
