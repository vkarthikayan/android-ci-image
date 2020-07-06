FROM phusion/baseimage:0.9.22

LABEL maintainer="anthonymonori@gmail.com"

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

## Set up Android related environment vars
ENV ANDROID_SDK_URL="https://dl.google.com/android/repository/sdk-tools-linux-3859397.zip" \
    ANDROID_HOME="/opt/android" \
    RUBY_MAJOR=2.2 \
    RUBY_VERSION=2.2.8 \
    RUBY_DOWNLOAD_SHA256=8f37b9d8538bf8e50ad098db2a716ea49585ad1601bbd347ef84ca0662d9268a \
    RUBYGEMS_VERSION=2.7.2 \
    FASTLANE_VERSION=2.64.0 \
    YARN_VERSION=1.3.2 \
    NODE_VERSION=14.5.0

ENV PATH $PATH:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS_VERSION

WORKDIR /opt

# Install Dependencies
COPY dependencies.txt /var/temp/dependencies.txt
RUN dpkg --add-architecture i386 && apt-get update
RUN apt-get install -y --allow-change-held-packages $(cat /var/temp/dependencies.txt)

# Install openjdk-8-jdk 
RUN apt-get update \
    && apt-get install -y openjdk-8-jdk \
    && apt-get autoremove -y \
    && apt-get clean

# Install ruby
RUN mkdir -p /usr/local/etc \
  	&& { \
  		echo 'install: --no-document'; \
  		echo 'update: --no-document'; \
  	} >> /usr/local/etc/gemrc

# some of ruby's build scripts are written in ruby so we purge this later to make sure our final image uses what we just built
RUN set -ex \
    && buildDeps='bison libgdbm-dev ruby' \
    && apt-get update \
    && apt-get install -y --no-install-recommends $buildDeps \
    && rm -rf /var/lib/apt/lists/* \
    && wget --output-document=ruby.tar.gz --quiet http://cache.ruby-lang.org/pub/ruby/$RUBY_MAJOR/ruby-${RUBY_VERSION}.tar.gz \
    && echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.gz" | sha256sum -c - \
    && mkdir -p /usr/src/ruby \
    && tar -xzf ruby.tar.gz -C /usr/src/ruby --strip-components=1 \
    && rm ruby.tar.gz \
    && cd /usr/src/ruby \
    && { echo '#define ENABLE_PATH_CHECK 0'; echo; cat file.c; } > file.c.new && mv file.c.new file.c \
    && autoconf \
    && ./configure --disable-install-doc \
    && make -j"$(nproc)" \
    && make install \
    && apt-get purge -y --auto-remove $buildDeps \
    && gem update --system $RUBYGEMS_VERSION \
    && rm -r /usr/src/ruby \
    && apt-get autoremove -y \
    && apt-get clean

# install things globally, for great justice and don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_PATH="$GEM_HOME" \
  	BUNDLE_BIN="$GEM_HOME/bin" \
  	BUNDLE_SILENCE_ROOT_WARNING=1 \
  	BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $BUNDLE_BIN:$PATH
RUN mkdir -p "$GEM_HOME" "$BUNDLE_BIN" \
	  && chmod 777 "$GEM_HOME" "$BUNDLE_BIN"

# Install fastlane
RUN gem install fastlane -NV -v "$FASTLANE_VERSION"

# Android SDKs
RUN mkdir android \
    && cd android \
    && wget -O tools.zip ${ANDROID_SDK_URL} \
    && unzip tools.zip && rm tools.zip \
    && chmod a+x -R $ANDROID_HOME \
    && chown -R root:root $ANDROID_HOME \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && apt-get autoremove -y \
    && apt-get clean

# Pre-approved licenses << Might need to update regularly
RUN mkdir "${ANDROID_HOME}/licenses" || true \
    && echo -e "\nd56f5187479451eabf01fb78af6dfcb131a6481e" > "${ANDROID_HOME}/licenses/android-sdk-license" \
    && echo -e "\n84831b9409646a918e30573bab4c9c91346d8abd" > "${ANDROID_HOME}/licenses/android-sdk-preview-license" \
    && echo -e "\n601085b94cd77f0b54ff86406957099ebe79c4d6" > "${ANDROID_HOME}/licenses/android-googletv-license" \
    && echo -e "\n33b6a2b64607f11b759f320ef9dff4ae5c47d97a" > "${ANDROID_HOME}/licenses/google-gdk-license" \
    && echo -e "\nd975f751698a77b662f1254ddbeed3901e976f5a" > "${ANDROID_HOME}/licenses/intel-android-extra-license" \
    && echo -e "\ne9acab5b5fbb560a72cfaecce8946896ff6aab9d" > "${ANDROID_HOME}/licenses/mips-android-sysimage-license"

# Copy list of Android SDK packages to be installed
COPY android-packages.txt /var/temp/android-packages.txt

# Install SDK packages
RUN mkdir ~/.android \
    && touch ~/.android/repositories.cfg \
    && sdkmanager --package_file="/var/temp/android-packages.txt" --channel=0 --sdk_root="$ANDROID_HOME" --verbose

# Install Node.js 9 + npm + yarn
RUN groupadd --gid 1000 node \
  && useradd --uid 1000 --gid node --shell /bin/bash --create-home node

RUN set -ex \
  && for key in \
    94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
    FD3A5288F042B6850C66B31F09FE44734EB7990E \
    71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
    DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
    C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
    B9AE9905FFD7803F25714661B63B535A4C206CA9 \
    56730D5401028683275BD23C23EFEFE93C4CFFFE \
    77984A986EBC2AA786BC0F66B01FBB92821C587A \
  ; do \
    gpg --keyserver pgp.mit.edu --recv-keys "$key" || \
    gpg --keyserver keyserver.pgp.com --recv-keys "$key" || \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key" ; \
  done

RUN ARCH= && dpkgArch="$(dpkg --print-architecture)" \
  && case "${dpkgArch##*-}" in \
    amd64) ARCH='x64';; \
    ppc64el) ARCH='ppc64le';; \
    s390x) ARCH='s390x';; \
    arm64) ARCH='arm64';; \
    armhf) ARCH='armv7l';; \
    i386) ARCH='x86';; \
    *) echo "unsupported architecture"; exit 1 ;; \
  esac \
  && curl -SLO "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH.tar.xz" \
  && curl -SLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
  && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
  && grep " node-v$NODE_VERSION-linux-$ARCH.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
  && tar -xJf "node-v$NODE_VERSION-linux-$ARCH.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
  && rm "node-v$NODE_VERSION-linux-$ARCH.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt \
  && ln -s /usr/local/bin/node /usr/local/bin/nodejs

RUN set -ex \
  && for key in \
    6A010C5166006599AA17F08146C2130DFD2497F5 \
  ; do \
    gpg --keyserver pgp.mit.edu --recv-keys "$key" || \
    gpg --keyserver keyserver.pgp.com --recv-keys "$key" || \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key" ; \
  done \
  && curl -fSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
  && curl -fSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
  && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && mkdir -p /opt/yarn \
  && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/yarn --strip-components=1 \
  && ln -s /opt/yarn/bin/yarn /usr/local/bin/yarn \
  && ln -s /opt/yarn/bin/yarn /usr/local/bin/yarnpkg \
  && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz

# Cleaning
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# GO to workspace
RUN mkdir -p /opt/workspace
WORKDIR /opt/workspace
