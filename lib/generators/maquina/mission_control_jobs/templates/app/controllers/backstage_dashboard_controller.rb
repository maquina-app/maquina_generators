# frozen_string_literal: true

# Admin overview — a backstage surface alongside the SolidErrors and Mission
# Control Jobs engines, under the same backstage Basic auth.
#
# Out of the box it shows the installed engine entry points and an empty metrics
# area. Populate @metrics in #index with aggregate, non-sensitive counts for
# your app — counts, not names or per-record detail.
class BackstageDashboardController < BackstageController
  layout "admin"

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

  # Same backstage credentials the engines use. The inherited
  # require_backstage_credentials guard already fails closed (503) when
  # credentials.backstage is absent, so this only has to compare.
  def authenticate_backstage
    authenticate_or_request_with_http_basic("Admin") do |username, password|
      backstage = Rails.application.credentials.backstage || {}

      ActiveSupport::SecurityUtils.secure_compare(username.to_s, backstage[:username].to_s) &
        ActiveSupport::SecurityUtils.secure_compare(password.to_s, backstage[:password].to_s)
    end
  end
end
