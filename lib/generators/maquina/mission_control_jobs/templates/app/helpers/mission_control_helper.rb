# frozen_string_literal: true

module MissionControlHelper
  def job_status_badge_variant(status)
    case status.to_s
    when "failed" then :destructive
    when "blocked" then :warning
    when "in_progress" then :primary
    when "scheduled" then :secondary
    when "finished" then :success
    when "queued", "pending" then :default
    else :outline
    end
  end

  def nav_icon_for_section(key)
    case key.to_s
    when "queues" then :inbox
    when "workers" then :activity
    when "recurring_tasks" then :clock
    else :list
    end
  end
end
