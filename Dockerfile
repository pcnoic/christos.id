FROM ruby:3.2-alpine AS builder

RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm

WORKDIR /app

COPY Gemfile Gemfile.lock ./

RUN gem install bundler:2.7.1 && bundle install

COPY . .

RUN bundle exec jekyll build

# ---

FROM nginx:alpine

COPY --from=builder /app/_site /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
