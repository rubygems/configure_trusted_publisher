# frozen_string_literal: true

require "command_kit"
require "command_kit/commands"
require "command_kit/interactive"
require "io/console"

require "bundler"
require "json"
require "open3"
require "rubygems/gemcutter_utilities"
require "yaml"

Gem.configuration.verbose = true

module ConfigureTrustedPublisher
  class GemcutterUtilities
    include Gem::GemcutterUtilities

    attr_reader :options

    def initialize(say:, ask:, ask_for_password:, terminate_interaction:, otp:)
      @options = {
        otp:
      }
      @say = say
      @ask = ask
      @ask_for_password = ask_for_password
      @terminate_interaction = terminate_interaction
      @api_keys = {}
    end

    def say(...)
      @say.call(...)
    end

    def ask(...)
      @ask.call(...)
    end

    def ask_for_password(...)
      @ask_for_password.call(...)
    end

    def get_mfa_params(...)
      { "expires_at" => (Time.now + (15 * 60)).strftime("%Y-%m-%d %H:%M %Z"), "mfa" => false }
    end

    def terminate_interaction(...) = @terminate_interaction.call(...)

    def api_key
      return @api_keys[@host] if @api_keys[@host]

      if ENV["GEM_HOST_API_KEY"]
        ENV["GEM_HOST_API_KEY"]
      elsif options[:key]
        verify_api_key options[:key]
      end
    end

    def set_api_key(host, key)
      @api_keys[host] = key
    end

    def rubygems_api_request(*args, **, &)
      # pp(args:, **)
      resp = super(*args, **) do |req|
        yield(req)
        # pp(req: {
        #      method: __method__,
        #      req:,
        #      url: req.uri,
        #      req_body: req.body
        #    })
        _ = req
      end
      # pp(resp: {
      #      method: __method__,
      #      resp:,
      #      resp_body: resp.body
      #    })
      _ = resp

      resp
    end

    # def mfa_unauthorized?(response)
    #   super.tap do |result|
    #     pp result => {
    #       method: __method__,
    #       response:,
    #       response_body: response.body
    #     }
    #   end
    # end

    # def api_key_forbidden?(response)
    #   super.tap do |result|
    #     pp result => {
    #       method: __method__,
    #       response:,
    #       response_body: response.body
    #     }
    #   end
    # end
  end

  class CLI
    include CommandKit::Commands

    command_name "configure_trusted_publisher"

    class Rubygem < CommandKit::Command
      include CommandKit::Options
      include CommandKit::Interactive

      option :name,
             value: {
               type: String
             },
             desc: "The name of the Rubygem to configure the trusted publisher for."

      option :otp,
             value: {
               type: String
             },
             desc: "The one-time password for multi-factor authentication."

      argument :repository, required: false, desc: "The repository to configure the trusted publisher for.",
                            usage: "REPOSITORY"

      def run(repository = ".")
        @gemspec_source = Bundler::Source::Gemspec.new({
                                                         "root_path" => Pathname(repository),
                                                         "path" => "."
                                                       })
        rubygem_name = options[:name]
        unless rubygem_name
          if gemspec_source.specs.size > 1
            raise "Multiple gemspecs found in #{repository}, please specify the gem name with --name"
          elsif gemspec_source.specs.empty?
            raise "No gemspecs found in #{repository}, please specify the gem name with --name"
          end

          rubygem_name = gemspec_source.specs.first.name
        end

        Open3.capture2e("bundle", "exec", "rake", "release", "--dry-run", chdir: repository).then do |output, status|
          unless status.success?
            abort "bundle exec rake release is not configured for #{rubygem_name} in #{repository}:\n#{output}"
          end
        end

        puts "Configuring trusted publisher for #{rubygem_name} in #{File.expand_path(repository)} for " \
             "#{github_repository.join('/')}"

        environment = add_environment
        write_release_action(repository, rubygem_name, environment:)

        gc = GemcutterUtilities.new(
          say: ->(msg) { puts msg },
          ask: lambda { |msg|
                 puts
                 ask msg.strip.chomp(":")
               },
          ask_for_password: lambda { |msg|
                              puts
                              ask_secret msg.strip.chomp(":")
                            },
          terminate_interaction: lambda { |msg|
                                   puts
                                   exit msg
                                 },
          otp: options[:otp]
        )
        gc.sign_in(scope: "configure_trusted_publishers") unless gc.api_key

        owner, name = github_repository
        config = {
          "trusted_publisher" => {
            "repository_name" => name,
            "repository_owner" => owner,
            "environment" => environment,
            "workflow_filename" => "push_gem.yml"
          }.compact,
          "trusted_publisher_type" => "OIDC::TrustedPublisher::GitHubAction"
        }

        gc.rubygems_api_request(
          :get,
          "api/v1/gems/#{rubygem_name}/trusted_publishers",
          scope: "configure_trusted_publishers"
        ) do |req|
          req["Accept"] = "application/json"
          req.add_field "Authorization", gc.api_key
        end.then do |resp| # rubocop:disable Style/MultilineBlockChain
          if resp.code != "200"
            abort "Failed to get trusted publishers for #{rubygem_name} (#{resp.code.inspect}):\n#{resp.body}"
          end

          existing = JSON.parse(resp.body)
          if (e = existing.find do |pub|
                config["trusted_publisher_type"] == pub["trusted_publisher_type"] &&
                config["trusted_publisher"].all? do |k, v|
                  pub["trusted_publisher"][k] == v
                end
              end)

            abort "Trusted publisher for #{rubygem_name} already configured for " \
                  "#{e.dig('trusted_publisher', 'name').inspect}"
          end
        end

        resp = gc.rubygems_api_request(
          :post,
          "api/v1/gems/#{rubygem_name}/trusted_publishers",
          scope: "configure_trusted_publishers"
        ) do |req|
          req["Content-Type"] = "application/json"
          req["Accept"] = "application/json"
          req.add_field "Authorization", gc.api_key

          req.body = config.to_json
        end

        if resp.code == "201"
          puts "Successfully configured trusted publisher for #{rubygem_name}:\n  " \
               "#{gc.host}/gems/#{rubygem_name}/trusted_publishers"
        else
          abort "Failed to configure trusted publisher for #{rubygem_name}:\n#{resp.body}"
        end
      end

      def github_repository
        [
          gemspec.metadata["source_code_uri"],
          gemspec.metadata["homepage_uri"],
          gemspec.metadata["bug_tracker_uri"],
          gemspec.homepage
        ].each do |uri|
          next unless uri

          if uri =~ %r{github.com[:/](?<owner>[^/]+)/(?<repo>[^/]+)}
            return Regexp.last_match[:owner], Regexp.last_match[:repo]
          end
        end
        raise "No GitHub repository found for #{gemspec.name}"
      end

      def add_environment
        puts
        return unless ask_yes_or_no("Would you like to add a github environment to allow customizing " \
                                    "prerequisites for the action?")

        if Bundler.which("gh").nil?
          exit "The GitHub CLI (gh) is required to add a GitHub environment. " \
               "Please install it from https://cli.github.com/ and try again."
        end

        env_name = "rubygems.org"

        owner, name = github_repository
        puts "Adding GitHub environment to #{owner}/#{name} to protect the action"
        if (env = Open3.capture2e("gh", "api", "repos/#{owner}/#{name}/environments").then do |output, status|
              exit "Failed to list environments for #{owner}/#{name} using `gh api`:\n#{output}" unless status.success?

              JSON.parse(output)["environments"].find { |e| e["name"] == env_name }
            end)

          puts
          puts "Environment 'rubygems.org' already exists for #{owner}/#{name}:\n  #{env['html_url']}"
        else
          Open3.capture2e("gh", "api", "--method", "PUT",
                          "repos/#{owner}/#{name}/environments/#{env_name}").then do |output, status|
            unless status.success?
              exit "Failed to create rubygems.org environment for #{owner}/#{name} using `gh api`:\n#{output}"
            end

            env = JSON.parse(output)
            puts
            puts "Created environment 'rubygems.org' for #{owner}/#{name}:\n  #{env['html_url']}"
          end
        end

        env_name
      end

      attr_reader :gemspec_source

      def gemspec
        gemspec_source.specs.first
      end

      def write_release_action(repository, rubygem_name, environment: nil)
        tag = "Automatically when a new tag matching v* is pushed"
        manual = "Manually by running a GitHub Action"
        puts
        response = ask_multiple_choice(
          "How would you like releases for #{rubygem_name} to be triggered?", [
            tag,
            manual
          ],
          default: "2"
        )

        action_file = File.expand_path(".github/workflows/push_gem.yml", repository)
        return unless check_action(action_file)

        File.write(
          action_file,
          [
            "name: Push Gem",
            nil,
            "on:",
            "  #{response == tag ? "push:\n    tags:\n      - 'v*'" : 'workflow_dispatch:'}",
            nil,
            "permissions:",
            "  contents: read",
            nil,
            "jobs:",
            "  push:",
            "    if: github.repository == '#{github_repository.join('/')}'",
            "    runs-on: ubuntu-latest",
            if environment
              "\n    environment:\n      name: #{environment}\n      url: https://rubygems.org/gems/#{rubygem_name}\n"
            end,
            "    permissions:",
            "      contents: write",
            "      id-token: write",
            nil,
            "    steps:",
            "      # Set up",
            "      - name: Harden Runner",
            "        uses: step-security/harden-runner@a4aa98b93cab29d9b1101a6143fb8bce00e2eac4 # v2.7.1",
            "        with:",
            "          egress-policy: audit",
            nil,
            "      - uses: actions/checkout@0ad4b8fadaa221de15dcec353f45205ec38ea70b # v4.1.4",
            "      - name: Set up Ruby",
            "        uses: ruby/setup-ruby@cacc9f1c0b3f4eb8a16a6bb0ed10897b43b9de49 # v1.176.0",
            "        with:",
            "          bundler-cache: true",
            "          ruby-version: ruby",
            nil,
            "      # Release",
            "      - uses: rubygems/release-gem@612653d273a73bdae1df8453e090060bb4db5f31 # v1",
            nil
          ].join("\n")
        )
        puts "Created #{action_file}"
      end

      def check_action(action_file)
        return FileUtils.mkdir_p(File.dirname(action_file)) || true unless File.exist?(action_file)

        puts
        response = ask_yes_or_no(
          "#{action_file} already exists, overwrite?",
          default: false
        )
        return if response == "No"

        true
      end
    end

    command Rubygem
  end
end
