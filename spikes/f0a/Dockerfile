# F0-A spike toolchain — isolated, disposable. Not a production build image.
# Build:  docker build -t drinphone-spike:f0a spikes/f0a
# Remove: docker rmi drinphone-spike:f0a
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG FLUTTER_VERSION=3.47.8
ARG FLUTTER_SHA256=baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2
ARG CMDLINE_TOOLS=commandlinetools-linux-16111833_latest.zip
ARG CMDLINE_TOOLS_SHA1=e025545c62a8e64c7559119566a569fb1dec5f60

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip file python3 \
      openjdk-17-jdk-headless \
      clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev \
      xvfb xauth libasound2t64 libpulse0 \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 -s /bin/bash dev || usermod -l dev -d /home/dev -m $(id -nu 1000)
ENV ANDROID_HOME=/opt/android-sdk \
    FLUTTER_HOME=/opt/flutter \
    PUB_CACHE=/home/dev/.pub-cache
ENV PATH=$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH

RUN curl -fsSLo /tmp/flutter.tar.xz \
      https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/flutter.tar.xz -C /opt && rm /tmp/flutter.tar.xz \
    && curl -fsSLo /tmp/clt.zip https://dl.google.com/android/repository/${CMDLINE_TOOLS} \
    && echo "${CMDLINE_TOOLS_SHA1}  /tmp/clt.zip" | sha1sum -c - \
    && mkdir -p $ANDROID_HOME/cmdline-tools && unzip -q /tmp/clt.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest && rm /tmp/clt.zip \
    && chown -R 1000:1000 /opt/flutter $ANDROID_HOME

USER 1000:1000
RUN yes | sdkmanager --licenses >/dev/null \
    && sdkmanager "platform-tools" \
    && git config --global --add safe.directory '*' \
    && flutter config --no-analytics --enable-linux-desktop \
    && flutter precache --android --linux
WORKDIR /work
