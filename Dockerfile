FROM ruby:3.4.8-slim

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      libsqlite3-dev \
      libssl-dev \
      libyaml-dev \
      pkg-config \
 && rm -rf /var/lib/apt/lists/*

ENV BUNDLE_PATH=/bundle \
    BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_JOBS=4

WORKDIR /gem

COPY fizzy-oidc.gemspec Gemfile Rakefile ./
COPY lib/fizzy/oidc/version.rb ./lib/fizzy/oidc/version.rb

RUN bundle install

COPY . .

CMD ["bundle", "exec", "rake", "test"]
