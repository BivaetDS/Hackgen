FROM ruby:3.3-slim AS builder

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development

WORKDIR /workspace

RUN apt-get update \
    && apt-get install --yes --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

FROM ruby:3.3-slim

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development

WORKDIR /workspace

COPY --from=builder /usr/local/bundle /usr/local/bundle
RUN groupadd --system integrator && useradd --system --gid integrator --create-home integrator
COPY --chown=integrator:integrator . .
RUN mkdir -p /workspace/output && chown integrator:integrator /workspace/output

USER integrator
ENTRYPOINT ["bundle", "exec", "ruby", "bin/integrate"]
