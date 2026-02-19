FROM ruby:4.0.1-alpine3.23

WORKDIR /wp2txt
COPY . ./
RUN rm -f Gemfile.lock

# Install dependencies (git is required by gemspec's `git ls-files`)
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
      linux-headers libxml2-dev make gcc libc-dev bash \
      sqlite-dev git && \
    apk add --no-cache -t .build-packages \
      build-base curl-dev wget && \
    git init && git add -A && \
    bundle install -j4 && \
    apk del .build-packages

# lbzip2 is not available as an Alpine package; build from source
RUN apk add --no-cache build-base wget && \
    wget https://github.com/kjn/lbzip2/releases/download/v2.5/lbzip2-2.5.tar.gz -O lbzip2.tar.gz && \
    tar -xf lbzip2.tar.gz && cd lbzip2-2.5 && \
    ./configure && make && make install && \
    cd .. && rm -rf lbzip2* && \
    apk del build-base wget

WORKDIR /
ENV PATH=/wp2txt/bin:$PATH
CMD ["bash"]
