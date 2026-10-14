# Receives Content Security Policy violation reports. Browsers post them with no
# cookie and no CSRF token, in either the legacy report-uri shape
# (application/csp-report) or the Reporting API's (application/reports+json),
# so this is an API controller that reads the raw body itself.
#
# Always 204 for a report it could read — a browser does nothing with the
# answer — and best effort: a locked security database must never turn a
# report into a 500 that the browser retries.
class CspReportsController < ActionController::API
  MAX_BYTES = 64.kilobytes

  def create
    body = request.body.read(MAX_BYTES + 1).to_s
    return head 413 if body.bytesize > MAX_BYTES

    Security::CspViolation.record_report!(body, ip: request.remote_ip, user_agent: request.user_agent)
    head :no_content
  rescue JSON::ParserError
    head :bad_request
  rescue => error
    Rails.logger.error "[CSP] report not recorded: #{error.class}: #{error.message}"
    head :no_content
  end
end
