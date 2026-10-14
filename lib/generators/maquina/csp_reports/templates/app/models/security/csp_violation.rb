# One Content Security Policy violation a browser reported to CspReportsController.
# Rows are written once and never updated; they are what tells you whether the
# policy is ready to enforce (report-only) or what it is breaking (enforced).
#
# Browsers send two shapes. The legacy `report-uri` one is a single object,
# `{"csp-report": {"blocked-uri": ..., ...}}` (Content-Type application/csp-report);
# the Reporting API one is an array of `{"type": "csp-violation", "body": {...}}`
# (application/reports+json) with camelCase keys. Both normalize to the same row.
class Security::CspViolation < Security::Record
  RETENTION = 30.days

  # Violations caused by the reader's own browser extensions say nothing about
  # the app, and they are most of the volume.
  NOISE_SCHEMES = %w[chrome-extension moz-extension safari-extension safari-web-extension ms-browser-extension].freeze

  FIELD_LIMIT = 1024
  SAMPLE_LIMIT = 256

  LEGACY_KEYS = {
    "document-uri" => :document_uri, "blocked-uri" => :blocked_uri,
    "effective-directive" => :effective_directive, "violated-directive" => :effective_directive,
    "disposition" => :disposition, "source-file" => :source_file,
    "line-number" => :line_number, "column-number" => :column_number, "script-sample" => :sample
  }.freeze

  REPORTING_API_KEYS = {
    "documentURL" => :document_uri, "blockedURL" => :blocked_uri,
    "effectiveDirective" => :effective_directive, "disposition" => :disposition,
    "sourceFile" => :source_file, "lineNumber" => :line_number,
    "columnNumber" => :column_number, "sample" => :sample
  }.freeze

  validates :effective_directive, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :within, ->(window) { where(created_at: window.ago..) }
  scope :expired, -> { where(created_at: ...RETENTION.ago) }

  # Records every violation in a raw report body; returns how many were kept.
  # Raises JSON::ParserError on a body that isn't JSON.
  def self.record_report!(raw, ip:, user_agent:)
    violations = parse(raw).reject { |attrs| noise?(attrs) }
    violations.each do |attrs|
      create!(attrs.merge(ip:, user_agent: user_agent&.truncate(FIELD_LIMIT, omission: "")))
    end
    violations.size
  end

  def self.parse(raw)
    payload = JSON.parse(raw)
    reports = payload.is_a?(Array) ? payload : [payload]

    reports.filter_map do |report|
      next unless report.is_a?(Hash)

      if report.key?("csp-report")
        normalize(report["csp-report"], LEGACY_KEYS)
      elsif report["type"] == "csp-violation"
        normalize(report["body"], REPORTING_API_KEYS)
      end
    end
  end

  def self.noise?(attrs)
    [attrs[:blocked_uri], attrs[:source_file]].compact.any? do |uri|
      NOISE_SCHEMES.any? { |scheme| uri.start_with?("#{scheme}:") }
    end
  end

  def self.normalize(body, keys)
    return unless body.is_a?(Hash)

    attrs = keys.each_with_object({}) do |(key, attribute), acc|
      acc[attribute] ||= body[key] if body.key?(key)
    end
    # The directive alone (`script-src`), not the whole violated policy line.
    attrs[:effective_directive] = attrs[:effective_directive].to_s.split.first
    # URLs lose their query and fragment: a reported URL can carry a token.
    %i[document_uri blocked_uri source_file].each { |key| attrs[key] = strip_url(attrs[key]) }
    attrs[:sample] = attrs[:sample]&.to_s&.truncate(SAMPLE_LIMIT, omission: "")
    %i[line_number column_number].each { |key| attrs[key] = attrs[key]&.to_i }
    attrs.transform_values { |value| value.is_a?(String) ? value.truncate(FIELD_LIMIT, omission: "") : value }
  end

  def self.strip_url(value)
    value&.to_s&.split(/[?#]/, 2)&.first
  end
  private_class_method :normalize, :strip_url
end
