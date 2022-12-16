FROM ruby:3.1.3-alpine3.17

WORKDIR /wp2txt
COPY . ./
RUN rm -Rf wp2txt/Gemfile.lock

RUN apk update && \
    apk upgrade && \
    apk add --no-cache linux-headers libxml2-dev make gcc libc-dev bash && \
    apk add --no-cache -t .build-packages --no-cache build-base curl-dev wget gcompat && \
    bundle install -j4

RUN wget https://fossies.org/linux/privat/lbzip2-2.5.tar.gz -O lbzip2.tar.gz && \
    tar -xvf lbzip2.tar.gz && cd lbzip2-2.5 && \
    bash configure && make && make install && \
    cd .. && rm -rf lbzip2*

WORKDIR /
ENV PATH $PATH:/wp2txt/bin
CMD ["bash"]
