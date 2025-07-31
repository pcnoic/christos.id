FROM ruby:3.2-alpine

RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm

WORKDIR /app

COPY Gemfile Gemfile.lock ./

RUN gem install bundler:2.7.1 && bundle install

COPY . .

EXPOSE 4000

CMD ["bundle", "exec", "jekyll", "serve", "--host", "0.0.0.0", "--port", "4000", "--livereload"]