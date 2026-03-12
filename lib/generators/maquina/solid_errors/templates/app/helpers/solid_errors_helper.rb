module SolidErrorsHelper
  def severity_badge_variant(error)
    case error.severity.to_s
    when "fatal" then :destructive
    when "warning" then :warning
    else :default
    end
  end
end
