FROM redis

ENV APP_ROOT /meeseeker
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
        ruby \
        ruby-dev

RUN gem update --system
RUN gem install bundler

# copy in everything from repo
COPY . .

RUN chmod +x /meeseeker/bin/meeseeker

RUN bundle config --global silence_root_warning 1
RUN bundle install

CMD /usr/local/bin/redis-server --daemonize yes && bundle exec rake sync

EXPOSE 6379
