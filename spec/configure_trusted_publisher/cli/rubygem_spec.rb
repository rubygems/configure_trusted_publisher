# frozen_string_literal: true

require "spec_helper"
require "configure_trusted_publisher/cli"

RSpec.describe ConfigureTrustedPublisher::CLI::Rubygem do
  subject(:command) { described_class.new }

  let(:gc) do
    instance_double(ConfigureTrustedPublisher::GemcutterUtilities,
                    api_key: "key-123",
                    host: "https://rubygems.org").tap do |dbl|
      allow(dbl).to receive(:rubygems_api_request) do |method, path, **_kwargs, &block|
        req = Net::HTTP.const_get(method.to_s.capitalize).new("/#{path}")
        block&.call(req)
        Net::HTTP.start("rubygems.org", 443, use_ssl: true) { |http| http.request(req) }
      end
    end
  end

  let(:config) do
    {
      "trusted_publisher" => { "repository_owner" => "example", "repository_name" => "brand-new-gem",
                               "workflow_filename" => "push_gem.yml" },
      "trusted_publisher_type" => "OIDC::TrustedPublisher::GitHubAction"
    }
  end

  before do
    stub_request(:get, "https://rubygems.org/api/v1/gems/brand-new-gem/trusted_publishers")
      .to_return(status: 404, body: "This rubygem could not be found.")
  end

  context "when the gem does not exist and the user accepts" do
    let(:create_stub) do
      stub_request(:post, "https://rubygems.org/api/v1/oidc/pending_trusted_publishers")
        .with(body: hash_including("rubygem_name" => "brand-new-gem"))
        .to_return(status: 201, body: { id: 1 }.to_json, headers: { "Content-Type" => "application/json" })
    end

    before do
      allow(command).to receive(:ask_yes_or_no).and_return(true) # rubocop:disable RSpec/SubjectStub
      stub_request(:get, "https://rubygems.org/api/v1/oidc/pending_trusted_publishers")
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })
      create_stub
    end

    it "posts to the pending publishers endpoint" do
      command.configure_publisher(gc, "brand-new-gem", config)
      expect(create_stub).to have_been_requested
    end

    it "returns a message referencing the pending publishers page" do
      message = command.configure_publisher(gc, "brand-new-gem", config)
      expect(message).to include("/profile/oidc/pending_trusted_publishers")
    end
  end

  context "when the gem does not exist and the user declines" do
    before { allow(command).to receive(:ask_yes_or_no).and_return(false) } # rubocop:disable RSpec/SubjectStub

    it "aborts without calling the pending endpoint" do # rubocop:disable RSpec/MultipleExpectations
      expect { command.configure_publisher(gc, "brand-new-gem", config) }.to raise_error(SystemExit)
      expect(a_request(:post, "https://rubygems.org/api/v1/oidc/pending_trusted_publishers")).not_to have_been_made
    end
  end

  context "when the gem already exists" do
    let(:create_stub) do
      stub_request(:post, "https://rubygems.org/api/v1/gems/existing-gem/trusted_publishers")
        .to_return(status: 201, body: { id: 1 }.to_json, headers: { "Content-Type" => "application/json" })
    end

    before do
      stub_request(:get, "https://rubygems.org/api/v1/gems/existing-gem/trusted_publishers")
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })
      create_stub
    end

    it "POSTs to the gem endpoint" do
      command.configure_publisher(gc, "existing-gem", config)
      expect(create_stub).to have_been_requested
    end

    it "returns a message referencing the gem trusted publishers page" do
      message = command.configure_publisher(gc, "existing-gem", config)
      expect(message).to include("/gems/existing-gem/trusted_publishers")
    end

    it "never prompts the user" do
      allow(command).to receive(:ask_yes_or_no).and_return(nil) # rubocop:disable RSpec/SubjectStub
      command.configure_publisher(gc, "existing-gem", config)
      expect(command).not_to have_received(:ask_yes_or_no) # rubocop:disable RSpec/SubjectStub
    end
  end

  context "when an equivalent pending publisher already exists" do
    before do
      allow(command).to receive(:ask_yes_or_no).and_return(true) # rubocop:disable RSpec/SubjectStub
      stub_request(:get, "https://rubygems.org/api/v1/oidc/pending_trusted_publishers")
        .to_return(status: 200,
                   body: [{ "rubygem_name" => "brand-new-gem",
                            "trusted_publisher_type" => "OIDC::TrustedPublisher::GitHubAction",
                            "trusted_publisher" => { "repository_owner" => "example",
                                                     "repository_name" => "brand-new-gem",
                                                     "workflow_filename" => "push_gem.yml" } }].to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    it "aborts on dedup" do
      expect { command.configure_publisher(gc, "brand-new-gem", config) }.to raise_error(SystemExit)
    end
  end
end
