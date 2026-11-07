require "erb"

module Maquina
  module Generators
    # The MCP tool files the operational generators ship, shared by both sides
    # of the install-order contract: each sibling generator (solid_errors,
    # solid_queue, security, csp_reports) installs its own file when
    # app/models/mcp/tools.rb exists, and maquina:mcp installs the file of every
    # sibling whose marker it finds. Either order ends in the same files.
    #
    # Every method is private: a public method on a generator is a Thor step.
    module McpSiblingTools
      SIBLINGS = %i[solid_errors solid_queue security csp_reports].freeze
      GENERATORS_ROOT = File.expand_path("..", __dir__)

      # Files a sibling's tools call into, as [owning generator, path].
      SUPPORT_FILES = {
        solid_errors: %w[error_redactor errors_query failure_triage].map { |name| [:solid_errors, "app/agents/#{name}.rb"] },
        solid_queue: [[:solid_errors, "app/agents/error_redactor.rb"]],
        security: [],
        csp_reports: []
      }.freeze

      private

      def mcp_installed?
        File.exist?(File.join(destination_root, "app/models/mcp/tools.rb"))
      end

      # Installs app/models/mcp/tools/<sibling>.rb, its host-app test and the
      # files the tools call. Existing files are kept as they are. Returns true
      # when anything was written.
      def install_mcp_tools(sibling, write: false)
        sibling = sibling.to_sym
        raise ArgumentError, "unknown MCP sibling #{sibling.inspect}" unless SIBLINGS.include?(sibling)
        return false unless mcp_installed?

        files = SUPPORT_FILES.fetch(sibling) + [
          [sibling, "app/models/mcp/tools/#{sibling}.rb"],
          [sibling, "test/models/mcp/tools/#{sibling}_test.rb"]
        ]

        files.map { |owner, path| install_mcp_sibling_file(owner, path, write: write) }.any?
      end

      # The write tools each sibling's --mcp-write adds.
      WRITE_TOOLS = {
        solid_errors: %w[resolve_failure],
        solid_queue: %w[retry_failed_job discard_failed_job],
        security: %w[unban_address],
        csp_reports: []
      }.freeze

      # --mcp-write was asked for, but the sibling's tool file was already
      # there without every write tool, so install_mcp_tools kept it as it was.
      def mcp_write_pending?(sibling)
        path = File.join(destination_root, "app/models/mcp/tools/#{sibling}.rb")
        return false unless options[:mcp_write] && File.exist?(path)

        content = File.read(path)
        WRITE_TOOLS.fetch(sibling.to_sym).any? { |tool| !content.include?("def self.#{tool}") }
      end

      # The read-only variant of every sibling whose marker is present. Returns
      # the siblings that got files.
      def backfill_sibling_mcp_tools
        SIBLINGS.select { |sibling| mcp_sibling_marker?(sibling) && install_mcp_tools(sibling) }
      end

      def mcp_sibling_marker?(sibling)
        case sibling
        when :solid_errors then mcp_host_file?("config/initializers/solid_errors.rb")
        when :solid_queue then mcp_host_file?("config/solid_queue.yml") || mcp_host_file?("config/queue.yml")
        when :security then mcp_host_file?("app/models/security/abuse_event.rb")
        when :csp_reports
          mcp_host_file?("db/security_schema.rb") &&
            File.read(File.join(destination_root, "db/security_schema.rb")).include?(%("csp_violations"))
        end
      end

      def mcp_host_file?(path)
        File.exist?(File.join(destination_root, path))
      end

      # Thor's copy_file and template look the source up through source_paths,
      # which only holds the running generator's templates, so the source is
      # read by absolute path and written with create_file. A `.tt` source is
      # ERB with `write` as its only local.
      def install_mcp_sibling_file(owner, path, write:)
        return false if mcp_host_file?(path)

        source = File.join(GENERATORS_ROOT, owner.to_s, "templates", path)
        content = if File.exist?("#{source}.tt")
          ERB.new(File.read("#{source}.tt"), trim_mode: "-").result_with_hash(write: write)
        else
          File.read(source)
        end

        create_file path, content
        true
      end
    end
  end
end
