# Use a stable base operating system + the instructions currently leverage 
# a debian based package architecture.
#
# Default to linux/amd64 as running the dev container without this specified (on arm hosts), an error for adb is thrown.
# Setting the platform to linux/amd64 resolves this as the libraries required are loaded in.
#
# Note: This is a limitation on Android development tools, and not a limitation of the Flutter framework itself, as `adb`
#       requires libraries from a 64-bit host.
ARG platform=linux/amd64
FROM --platform=${platform} debian:13-slim AS base

USER root

# Setup the base dependencies to be updated.
RUN apt-get update -y && \
    apt-get upgrade -y

# Since we want to enable as many platforms as possible we should download both the
# core + linux + web + sqlite3 depenedencies.
RUN apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    mesa-utils \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-12-dev \
    sqlite3 \
    openjdk-25-jre-headless \
    chromium-shell

# We need a layer of the container to be dynamically built; including updates as needed for the sdks and licenses.
FROM --platform=${platform} base AS environment

USER root
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

WORKDIR /opt

RUN mkdir -p android-sdk && \
    chmod -R 775 android-sdk && \
    chown -R root:${USERNAME} android-sdk

# Flutter requires at least API 36.0
ARG ANDROID_SDK_VERSION=36
ENV ANDROID_HOME=/opt/android-sdk

# Configure the Android SDK conmmand line tools.
COPY cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest/
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${PATH}"

RUN echo "y" | sdkmanager --install --sdk_root="${ANDROID_HOME}" \
    "platforms;android-${ANDROID_SDK_VERSION}" \
    "build-tools;${ANDROID_SDK_VERSION}.0.0" \
    "platform-tools"

# Ensure that all licenses have required acceptances as root.
RUN yes | sdkmanager --licenses

# Enable flutter web dev support with minimum shell.
# Note: A quick way to swap to a headful instance would be to install chromium, but that instance would require more setup
#   to do GPU passthrough, which is well beyond our current needs.
ENV CHROME_EXECUTABLE=chromium-shell

# Download the current stable release with whatever hotfixes.
RUN git clone -b stable --depth 1 https://github.com/flutter/flutter.git && \
    git config --global --add safe.directory /opt/flutter

RUN chmod -R 775 flutter && \
    chown -R root:${USERNAME} flutter

FROM --platform=${platform} environment AS container
USER $USERNAME
EXPOSE 8080

# Enable the user to pre-configure their environment, using the $HOME directory as the parent of the active dev space.
WORKDIR /home/$USERNAME/workspace

# Fix an issue in line feed endings on windows host machines & ensure that the local user has the safe directory for the
# Flutter SDK.
RUN git config --global core.eol lf && \
    git config --global core.autocrlf input && \
    git config --global --add safe.directory /opt/flutter

# Add Flutter & pub installs to path.
ENV PATH="/opt/flutter/bin:/opt/flutter/.pub-cache/bin:$PATH"

# Ensure that the docker container has a cached acceptance of licenses under user
RUN yes | flutter doctor --android-licenses

COPY web_dev_config.yaml .

ENTRYPOINT ["/bin/bash"]
