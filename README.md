# ConfigureTrustedPublisher

A small CLI to automate the process of configuring a trusted publisher for a gem.

## Usage

To configure a trusted publisher for a gem, run the following command:

```console
$ gem exec configure_trusted_publisher rubygem
Configuring trusted publisher for rubygem0 in /Users/segiddins/Development/github.com/rubygems/configure_trusted_publisher for rubygems/configure_trusted_publisher
Enter your https://rubygems.org credentials.
Don't have an account yet? Create one at https://rubygems.org/sign_up
Username/email: : gem-author
      Password: :

  1) Automatically when a new tag matching v* is pushed
  2) Manually by running a GitHub Action

How would you like releases for rubygem0 to be triggered? (1, 2) [2]: 2

Successfully configured trusted publisher for rubygem0:
  https://rubygems.org/gems/rubygem0/trusted_publishers
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/rubygems/configure_trusted_publisher>.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
