FROM circleci/ruby:2.6.6

WORKDIR /app

COPY . .
RUN bundle install
