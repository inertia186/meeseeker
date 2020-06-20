FROM redis

ENV APP_ROOT /meeseeker
ENV MEESEEKER_MAX_KEYS 300000
WORKDIR /meeseeker

# Dependencies
RUN \
    apt-get update && \
    apt-get install -y \
        curl \
        bzip2 \
        build-essential \
        libssl-dev \
        libreadline-dev \
        zlib1g-dev \
        nodejs \
        procps && \
    apt-get clean && \
    command curl -sSL https://rvm.io/mpapis.asc | gpg --import - && \
    command curl -sSL https://rvm.io/pkuczynski.asc | gpg --import - && \
    curl -sSL https://get.rvm.io | bash -s stable --ruby

RUN \
  /bin/bash -c " \
    source /usr/local/rvm/scripts/rvm && \
    gem update --system && \
    gem install bundler \
  "

# copy in everything from repo
COPY bin bin
COPY lib lib
COPY Gemfile .
COPY meeseeker.gemspec .
COPY Rakefile .
COPY LICENSE .
COPY README.md .

RUN chmod +x /meeseeker/bin/meeseeker

RUN \
  /bin/bash -c " \
    source /usr/local/rvm/scripts/rvm && \
    bundle config --global silence_root_warning 1 && \
    bundle install \
  "

ENTRYPOINT \
  /usr/local/bin/redis-server --daemonize yes && \
  /bin/bash -c " \
    source /usr/local/rvm/scripts/rvm && \
    while :; do bundle exec rake sync; echo Restarting meeseeker; sleep 3; done \
  "

EXPOSE 6379
