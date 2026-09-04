FROM debian:trixie-slim AS base
    ARG GID=1000
    RUN groupadd gridapp -g $GID
    ARG UID=1000
    RUN useradd -m gridapp -u $UID -g $GID
    ENV HOME=/home/gridapp
    WORKDIR $HOME

FROM base AS updated-base
    RUN apt update
    RUN apt install -y --no-install-recommends git
    RUN git config --system --add safe.directory /opt/flutter

FROM updated-base AS common-android
    ARG ANDROID_CMDLINE_TOOLS_SHORT=20.0
    ARG ANDROID_CMDLINE_TOOLS_LONG=14742923
    ARG JDK=21

FROM updated-base AS setup-rust
    ## CARGO_HOME=$HOME/.cargo RUSTUP_HOME=$HOME/.rustup ??CARGO_INCREMENTAL=0 ??CARGO_TERM_COLOR=always
    RUN apt install -y --no-install-recommends curl ca-certificates
    RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain none -y

FROM updated-base AS setup-flutter
    ## PATH=$PATH:/opt/flutter/bin
    RUN apt install -y --no-install-recommends curl ca-certificates xz-utils
    ARG FLUTTER=3.41.5
    RUN mkdir -p /opt/flutter
    RUN curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_$FLUTTER-stable.tar.xz | tar -xJ -C /opt

FROM common-android AS setup-jdk
    RUN apt install -y --no-install-recommends wget gpg ca-certificates
    RUN wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg
    RUN echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list
    RUN apt update
    RUN apt install -y --no-install-recommends temurin-$JDK-jdk
    ENV JAVA_HOME=/usr/lib/jvm/temurin-$JDK-jdk-amd64

FROM setup-jdk AS setup-android
    ## ANDROID_HOME=$HOME/.android/sdk
    ## ANDROID_SDK_ROOT=$HOME/.android/sdk
    ## PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/$ANDROID_CMDLINE_TOOLS_SHORT/bin
    RUN apt install -y --no-install-recommends curl ca-certificates libarchive-tools
    ENV ANDROID_HOME=$HOME/.android/sdk
    ENV ANDROID_SDK_ROOT=$ANDROID_HOME
    ENV PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/$ANDROID_CMDLINE_TOOLS_SHORT/bin
    RUN mkdir -p $ANDROID_SDK_ROOT/cmdline-tools/$ANDROID_CMDLINE_TOOLS_SHORT
    RUN touch $ANDROID_SDK_ROOT/repositories.cfg

    RUN curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-$(echo $ANDROID_CMDLINE_TOOLS_LONG)_latest.zip -o - | bsdtar -xf - --strip-components=1 -C $ANDROID_SDK_ROOT/cmdline-tools/$ANDROID_CMDLINE_TOOLS_SHORT
    RUN chmod +x $ANDROID_SDK_ROOT/cmdline-tools/$ANDROID_CMDLINE_TOOLS_SHORT/bin/*
    RUN echo "$(yes | sdkmanager --licenses)"
    RUN sdkmanager "ndk;28.0.12433566" "platforms;android-35" "platforms;android-36"
    RUN rm -rf $ANDROID_SDK_ROOT/.temp $ANDROID_SDK_ROOT/.cache

FROM base AS setup-kotlin
    ARG KOTLIN=2.1.0
    RUN mkdir -p $HOME/.gradle/init.d
    RUN cat > $HOME/.gradle/init.d/kotlin.gradle <<EOF
    initscript {
        repositories {
            gradlePluginPortal()
            google()
            mavenCentral()
        }
        dependencies {
            classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:$KOTLIN"
        }
    }

    allprojects {
        pluginManager.withPlugin("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
        pluginManager.withPlugin("com.android.application") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
EOF

FROM updated-base AS setup-gradle
    RUN apt install -y --no-install-recommends curl ca-certificates libarchive-tools
    RUN mkdir -p /opt/gradle
    COPY android/gradle/wrapper/gradle-wrapper.properties $HOME/android/gradle/wrapper/gradle-wrapper.properties
    RUN curl -fsSL $(grep '^distributionUrl=' $HOME/android/gradle/wrapper/gradle-wrapper.properties | cut -d= -f2- | xargs) | bsdtar -xf - --strip-components=1 -C /opt/gradle
    RUN rm -rf /opt/gradle/src /opt/gradle/docs
    RUN chmod +x /opt/gradle/bin/gradle

FROM setup-flutter AS setup-flutter-dependencies
    RUN /opt/flutter/bin/flutter --disable-analytics
    RUN /opt/flutter/bin/flutter precache --android
    COPY patches /workspace/patches
    COPY pubspec.yaml pubspec.lock /workspace/
    RUN /opt/flutter/bin/flutter pub get -C /workspace

FROM setup-jdk AS setup-gradle-dependencies
    ENV GIT_TERMINAL_PROMPT=0
    RUN git config --global credential.helper ""
    RUN git config --global --unset-all credential.helper || true
    # ENV CARGO_HOME=$HOME/.cargo
    # ENV RUSTUP_HOME=$HOME/.rustup
    ENV ANDROID_HOME=$HOME/.android/sdk
    ENV ANDROID_SDK_ROOT=$ANDROID_HOME

    COPY --from=setup-flutter /opt/flutter /opt/flutter
    RUN /opt/flutter/bin/flutter --disable-analytics
    COPY --from=setup-gradle /opt/gradle /opt/gradle
    # COPY --from=setup-rust $CARGO_HOME $CARGO_HOME
    # COPY --from=setup-rust $RUSTUP_HOME $RUSTUP_HOME
    COPY --from=setup-android $ANDROID_SDK_ROOT $ANDROID_SDK_ROOT
    COPY --from=setup-kotlin $HOME/.gradle/init.d/kotlin.gradle $HOME/.gradle/init.d/kotlin.gradle

    RUN cat > $HOME/.gradle/init.d/resolve-buildscript-dependencies.gradle <<'EOF'
    gradle.allprojects {
        afterEvaluate {
            buildscript.configurations.configureEach {
                if (canBeResolved) {
                    resolve()
                }
            }
        }
    }
EOF

    COPY android/app/build.gradle $HOME/android/app/
    COPY android/gradle/wrapper/gradle-wrapper.properties $HOME/android/gradle/wrapper/gradle-wrapper.properties
    COPY android/build.gradle android/gradle.properties android/settings.gradle $HOME/android/
    RUN cat > $HOME/android/local.properties <<EOF
    sdk.dir=$HOME/.android/sdk
    flutter.sdk=/opt/flutter
    keyAlias=
    keyPassword=
    storeFile=local.properties
    storePassword=
EOF

    ENV GRADLE_USER_HOME=$HOME/.gradle
    ENV PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/$ANDROID_CMDLINE_TOOLS_SHORT/bin:$JAVA_HOME/bin:/opt/gradle/bin
    RUN cd $HOME/android && gradle wrapper --distribution-type all
    RUN cd $HOME/android && ./gradlew help
    RUN cd $HOME/android && ./gradlew dependencies
    RUN cd $HOME/android && ./gradlew :app:preBuild
    RUN cd $HOME/android && ./gradlew buildEnvironment
    RUN cd $HOME/android && ./gradlew projects

    RUN rm -rf $HOME/.gradle/daemon $HOME/.gradle/native $HOME/.gradle/notifications

FROM setup-jdk AS android-builder
    ENV GIT_TERMINAL_PROMPT=0
    RUN git config --global credential.helper ""
    RUN git config --global --unset-all credential.helper || true
    ENV CARGO_HOME=$HOME/.cargo
    ENV RUSTUP_HOME=$HOME/.rustup
    ENV ANDROID_HOME=$HOME/.android/sdk
    ENV ANDROID_SDK_ROOT=$ANDROID_HOME
    ENV GRADLE_USER_HOME=$HOME/.gradle
    ENV JAVA_HOME=/usr/lib/jvm/temurin-$JDK-jdk-amd64
    ENV PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/$ANDROID_CMDLINE_TOOLS_SHORT/bin:$JAVA_HOME/bin:/opt/flutter/bin

    RUN apt install -y --no-install-recommends build-essential

    COPY --chown=$UID:$GID --from=setup-flutter /opt/flutter /opt/flutter
    RUN mkdir -p /workspace
    RUN mkdir -p /workspace/.dart-tool
    RUN chown -R $UID:$GID /workspace/.dart-tool
    USER $UID:$GID
    RUN /opt/flutter/bin/flutter --disable-analytics
    USER root:root
    COPY --chown=$UID:$GID --from=setup-android $ANDROID_SDK_ROOT $ANDROID_SDK_ROOT
    RUN sdkmanager "platform-tools" "build-tools;35.0.0"
    RUN sdkmanager "build-tools;36.0.0" "platforms;android-33" "platforms;android-31" "platforms;android-34" "cmake;3.22.1"
    COPY --from=setup-rust $CARGO_HOME $CARGO_HOME
    COPY --from=setup-rust $RUSTUP_HOME $RUSTUP_HOME
    COPY --chown=$UID:$GID --from=setup-flutter-dependencies $HOME/.pub-cache $HOME/.pub-cache
    COPY --chown=$UID:$GID --from=setup-gradle-dependencies $HOME/.gradle $HOME/.gradle
    COPY --chown=$UID:$GID --from=setup-gradle-dependencies $HOME/android $HOME/android

    WORKDIR /workspace

    RUN cat > $HOME/docker-entrypoint <<'EOF'
    set -e

    mkdir -p /workspace/android/gradle/wrapper
    cp $HOME/android/gradlew $HOME/android/gradle.properties /workspace/android/
    cp $HOME/android/gradle/wrapper/gradle-wrapper.jar $HOME/android/gradle/wrapper/gradle-wrapper.properties /workspace/android/gradle/wrapper
    if [ ! -f /workspace/android/local.properties ]; then
        cp $HOME/android/local.properties /workspace/android/local.properties
    fi

    exec "$@"
EOF
    RUN chmod +x $HOME/docker-entrypoint
    USER $UID:$GID
    ENTRYPOINT [ "/bin/bash", "/home/gridapp/docker-entrypoint" ]