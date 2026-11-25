require_relative "config"

module JiraMultisite
  # Reads KEY=value pairs from a .env file into the environment.
  #
  # It keeps the API token out of the MCP client's config, where the apps show
  # it on screen. A variable that is already set wins, so credentials passed by
  # the client keep working.
  #
  # The format is deliberately small: one `KEY=value` per line, optional
  # `export`, optional quotes, `#` comments. No escapes, no interpolation, no
  # multi-line values. That is all a token needs, and it avoids a dependency.
  module EnvFile
    FILE_NAME = ".env"
    LINE = /\A(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\z/

    module_function

    # Where the server looks, in order. Earlier files win.
    def default_paths(env = ENV)
      sites_file = env.fetch("JIRA_SITES_FILE", Config::DEFAULT_PATH)
      [
        File.join(File.dirname(File.expand_path(sites_file)), FILE_NAME),
        File.expand_path("../../#{FILE_NAME}", __dir__),
      ].uniq
    end

    # Sets the variables that are missing (or empty) in `env` and returns
    # their names. A file that does not exist is not an error.
    def load(path, env: ENV, err: $stderr)
      return [] unless File.file?(path)

      warn_if_exposed(path, err)
      parse(File.read(path), path: path).filter_map do |key, value|
        next unless env[key].to_s.empty?

        env[key] = value
        key
      end
    end

    # Errors name the line number only: the line itself may hold a token.
    def parse(text, path: FILE_NAME)
      text.each_line.with_index(1).with_object({}) do |(line, number), pairs|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        match = LINE.match(line)
        raise ConfigError, "#{path}, line #{number}: expected KEY=value" unless match

        pairs[match[1]] = unquote(match[2])
      end
    end

    def unquote(value)
      quoted = value.match(/\A(["'])(.*?)\1\s*(?:#.*)?\z/)
      return quoted[2] if quoted

      value.sub(/\s+#.*\z/, "").strip
    end

    def warn_if_exposed(path, err)
      return if Gem.win_platform?
      return if (File.stat(path).mode & 0o077).zero?

      err.puts "jira-multisite-mcp: #{path} is readable by other users. Run: chmod 600 #{path}"
    end
  end
end
