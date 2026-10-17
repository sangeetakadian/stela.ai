FROM vercel/sandbox/node:24

ARG DEBIAN_FRONTEND=noninteractive

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    default-jdk-headless \
    gnupg \
    python3 \
  && install -d -m 0755 /usr/share/keyrings \
  && curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /usr/share/keyrings/dart.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" \
    > /etc/apt/sources.list.d/dart_stable.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends dart \
  && rm -rf /var/lib/apt/lists/*

USER ubuntu
WORKDIR /vercel
USER node
WORKDIR /home/node
