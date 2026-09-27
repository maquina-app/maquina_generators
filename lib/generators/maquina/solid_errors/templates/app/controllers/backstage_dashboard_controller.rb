# frozen_string_literal: true

# Admin overview — a backstage surface alongside the SolidErrors and Mission
# Control Jobs engines, under the same backstage Basic auth.
#
# Out of the box it shows the installed engine entry points and an empty metrics
# area. Populate @metrics in #index with aggregate, non-sensitive counts for
# your app — counts, not names or per-record detail.
class BackstageDashboardController < BackstageController
  layout "admin"

  before_action :require_backstage_credentials
  before_action :authenticate_backstage

  def index
    @generated_at = Time.current

    # Add overview metrics here. Each entry renders as a card:
    #
    #   @metrics = [
    #     {label: "Accounts", icon: :folder, value: Account.count, hint: "tenants"},
    #     {label: "Users", icon: :user, value: User.count, hint: "members"}
    #   ]
    #
    # Keep them aggregate-only. :total and :hint are optional.
    @metrics = []
  end

  private

  # Closed (503) until credentials.backstage is set. Without this an unset
  # username and password are both "", and an empty Basic header matches them.
  def require_backstage_credentials
    backstage = Rails.application.credentials.backstage || {}
    head :service_unavailable if backstage[:username].blank? || backstage[:password].blank?
  end

  # Same backstage credentials the engines use.
  def authenticate_backstage
    authenticate_or_request_with_http_basic("Admin") do |username, password|
      backstage = Rails.application.credentials.backstage || {}

      ActiveSupport::SecurityUtils.secure_compare(username.to_s, backstage[:username].to_s) &
        ActiveSupport::SecurityUtils.secure_compare(password.to_s, backstage[:password].to_s)
    end
  end
end
