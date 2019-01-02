require "json"

module Jam
  class Project
    class Specification
      def self.from_json(path)
        NotFoundError.raise_with(path: path) unless File.file?(path)

        Jam.logger.debug("Loading project from #{path.inspect}")
        new(JSON.parse(IO.read(path)))
      end

      attr_reader :hosts, :deploy_tasks, :plugins, :settings

      def initialize(spec)
        normalize_hosts(spec)
        @hosts = build_hosts(spec["hosts"])
        @environments = merge_environments(spec).freeze
        @deploy_tasks = (spec["deploy"] || []).freeze
        @plugins = (spec["plugins"] || []).freeze
        @settings = (spec["settings"] || {}).freeze
        freeze
      end

      def for_environment(env)
        if env.nil?
          raise_no_environment_specified unless environments.empty?
          self
        elsif env == :auto
          environments.values.first || self
        else
          environments.fetch(env) do
            raise_unknown_environment(env)
          end
        end
      end

      private

      attr_reader :environments

      # rubocop:disable Metrics/MethodLength
      def normalize_hosts(spec)
        return unless spec.key?("host")
        raise "Cannot specify both host and hosts" if spec.key?("hosts")

        host = Host.parse(spec.delete("host"))
        spec["hosts"] = {
          nil => {
            "address" => host.address,
            "port" => host.port,
            "roles" => host.roles,
            "user" => host.user
          }
        }
      end
      # rubocop:enable Metrics/MethodLength

      def build_hosts(spec_hosts)
        (spec_hosts || []).map do |name, meta|
          Host.new(
            name: name,
            address: meta["address"],
            port: meta["port"],
            roles: meta["roles"],
            user: meta["user"]
          )
        end
      end

      def merge_environments(spec)
        environments = spec.delete("environments") || {}
        environments.each_with_object({}) do |(name, env_spec), result|
          normalize_hosts(env_spec)
          merged = spec.merge(env_spec) do |key, orig, new|
            key == "settings" ? orig.merge(new) : new
          end
          result[name] = Specification.new(merged)
        end
      end

      def raise_no_environment_specified
        raise "No environment specified! "\
              "Must be one of #{environments.keys.inspect}"
      end

      def raise_unknown_environment(environment)
        message = "Unknown environment #{environment.inspect}. "
        message << if environments.empty?
                     "This project does not have any environments."
                   else
                     "Must be one of #{environments.keys.inspect}"
                   end
        raise message
      end
    end
  end
end