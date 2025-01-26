# ARG PREBUILT_LLVM_IMAGE=nbars/fuzztruction-llvm_debug:eb1d5065c560b3468fa0d34af3103359cd78c088
ARG PREBUILT_LLVM_IMAGE=nbars/fuzztruction-llvm_debug:llvmorg-17.0.6

FROM ${PREBUILT_LLVM_IMAGE} AS llvm

FROM ubuntu:24.04 AS dev
ENV DEBIAN_FRONTEND=noninteractive
# ENV CCACHE_DIR=/ccache
# ENV CCACHE_MAXSIZE=25G

RUN sed -i "s/^# deb-src/deb-src/g" /etc/apt/sources.list

RUN apt update -y && apt-mark hold "llvm-*" && apt-mark hold "clang-*"
RUN \
    apt update -y && \
    apt install -y aspell-en bear binutils-gold bison build-essential cm-super \
        cmake curl dvipng fdupes flex fonts-powerline g++ gcc-multilib git gosu htop \
        iproute2 iputils-ping libc++-dev libfdt-dev libglib2.0-dev libgmp-dev \
        libpixman-1-dev libz3-dev linux-tools-generic locales lsb-release lsof libssl-dev libtool \
        ltrace man mercurial nano nasm ncdu neovim ninja-build parallel powerline \
        psmisc python3-pip qpdf ripgrep rr rsync strace sudo texinfo texlive \
        texlive-fonts-recommended texlive-latex-extra tmux tree ubuntu-dbgsym-keyring \
        unzip valgrind virtualenv wget xdot zip zlib1g-dev zsh \
        graphviz-dev libcap-dev tcpflow gnutls-dev tcpdump graphviz-dev jq netcat-traditional \
        elfutils zstd pax-utils

RUN sudo pip3 install --break-system-packages mypy pylint matplotlib pyelftools lit pyyaml psutil pypcapkit awscli

# Copy prebuilt custom LLVM version
COPY --from=llvm /llvm/* /usr

RUN locale-gen en_US.UTF-8
ARG USER_UID=1000
ARG USER_GID=1000

#Enable sudo group
RUN echo "%sudo ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
WORKDIR /tmp

RUN update-locale LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8

# Install AFL++
COPY consumer /consumer
RUN LLVM_CONFIG=llvm-config cd /consumer/aflpp-consumer && make clean && make all && make install

# Make sure the loader finds our agent library.
COPY data/ld_fuzztruction.conf /etc/ld.so.conf.d/fuzztruction.conf

#Create group "user" or if there is a group with id USER_GID rename it to user.
RUN groupadd -g ${USER_GID} user || groupmod -g ${USER_GID} -n user $(getent group ${USER_GID} | cut -d: -f1)

#Create user "user" or if there is a use with id USER_UID rename it to user.
# -l -> https://github.com/moby/moby/issues/5419
RUN useradd -l --shell /bin/bash -c "" -m -u ${USER_UID} -g user -G sudo user || usermod -u ${USER_UID} -l user $(id -nu ${USER_UID})

# If we renamed an existing user, we need to make sure that its home directory is updated and owned by us.
RUN mkdir -p /home/user && \
    usermod -d /home/user user && \
    chown -R user:user /home/user

RUN gpasswd -a user user
RUN gpasswd -a user sudo

WORKDIR "/home/user"

RUN echo "set speller \"aspell -x -c\"" > /etc/nanorc

RUN cd /tmp && \
    apt install autoconf -y && \
    git clone https://github.com/NixOS/patchelf.git && \
    cd patchelf && \
    ./bootstrap.sh && \
    ./configure && \
    make && \
    make check && \
    make install

COPY env/check_env.sh /usr/bin/

# depot tools needed for webrtc()
# RUN cd / && git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
# ENV PATH "$PATH:/depot_tools"
# RUN chown user:user -R /depot_tools

USER user
#RUN wget -O ~/.gdbinit-gef.py -q https://gef.blah.cat/py \
COPY lib/gdbinit-gef.py ~/.gdbinit-gef.py
RUN echo source ~/.gdbinit-gef.py >> ~/.gdbinit

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y --default-toolchain nightly-2023-10-10
ENV PATH="/home/user/.cargo/bin:${PATH}"

RUN cd /tmp && \
    sh -c "$(wget -O- -4 https://raw.githubusercontent.com/deluan/zsh-in-docker/master/zsh-in-docker.sh)" -- \
    -t agnoster

# Install rr
RUN cd /tmp && \
    wget https://github.com/rr-debugger/rr/releases/download/5.7.0/rr-5.7.0-Linux-$(uname -m).deb && \
    sudo dpkg -i rr-5.7.0-Linux-$(uname -m).deb

COPY patches /tmp/patches

# # Install afl-net
# RUN sudo mkdir /competitors && \
#     sudo chown user:user -R /competitors && \
#     cd /competitors && \
#     git clone https://github.com/aflnet/aflnet.git && \
#     cd aflnet  && \
#     git checkout 62d63a59230bb5f5c6e54cddd381b9425dba3726 && \
#     git apply /tmp/patches/aflnet.patch && \
#     make clean all && \
#     cd  llvm_mode && \
#     make

# # Install SGFuzz
# RUN cd /competitors && \
#     git clone https://github.com/bajinsheng/SGFuzz.git && \
#     cd SGFuzz && \
#     git checkout 00dbbd70ba79f1bcff3f7dfdb4fda0645cf91225 && \
#     git apply /tmp/patches/sgfuzz.patch && \
#     ./build.sh && \
#     sudo cp libsfuzzer.a /usr/lib/libsFuzzer.a

# # Install hongfuzz netdrive that is used by SGFuzz
# RUN cd /competitors && \
#     git clone https://github.com/google/honggfuzz.git && \
#     cd honggfuzz && \
#     git checkout 6f89ccc9c43c6c1d9f938c81a47b72cd5ada61ba && \
#     CC=clang CFLAGS="-fsanitize=fuzzer-no-link -fsanitize=address" make libhfcommon/libhfcommon.a && \
#     CC=clang CFLAGS="-fsanitize=fuzzer-no-link -fsanitize=address -DHFND_RECVTIME=1" make libhfnetdriver/libhfnetdriver.a && \
#     sudo mv libhfcommon/libhfcommon.a /usr/lib/libhfcommon.a && \
#     sudo mv libhfnetdriver/libhfnetdriver.a /usr/lib/libhfnetdriver.a

# # Install StateAfl
# RUN sudo apt install -y tshark && sudo pip3 install --break-system-packages pyshark
# RUN cd /competitors && \
#     git clone https://github.com/stateafl/stateafl.git  && \
#     cd stateafl  && \
#     git checkout d923e22f7b2688db45b08f3fa3a29a566e7ff3a4  && \
#     git submodule init && \
#     git submodule update && \
#     git apply /tmp/patches/stateafl.patch && \
#     make -j  && \
#     cd llvm_mode  && \
#     rm -f libmvptree.a containers.a libtlsh.a && \
#     cd tlsh && \
#     git apply /tmp/patches/tlsh.patch && \
#     cd .. && \
#     make -j

# Pubkey part of /home/user/shared/fuzztruction-experiments/comparison-with-state-of-the-art/configurations/networked/dropbear/keys/ecdsa and .../rsa_key
# /home/user/fuzztruction/fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked/dropbear/consumer_afl_net/dropbear/dropbearkey ed25519  -y -f $PWD/ed25519
RUN sudo chown -R user:user /home/user && \
    mkdir -p /home/user/.ssh && \
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDtqJ7zOtqQtYqOo0CpvDXNlMhV3HeJDpjrASKGLWdop" > /home/user/.ssh/authorized_keys && \
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQDP+l17CnFodziIFoUI/xrKiJuct7eK8O6GSr5hH+a3rC1zn4bfbvUE2+io1ftzvnelaKxBOJWXA5xYH6kBDnGiUqhDqHrmI/1slBxUA94QVabWqqhLNLnxtljuDVOkcV6V8iLkDR+jIKiqXjbvWnyItMG/RTydLc2l6dfm9/1BrQ==" >> /home/user/.ssh/authorized_keys && \
    chmod 600 /home/user/.ssh/authorized_keys

RUN sudo apt purge ccache -y


FROM dev AS prebuilt

USER user
RUN mkdir /home/user/fuzztruction
WORKDIR /home/user/fuzztruction

RUN mkdir -p lib
COPY --chown=user:user ./lib/proc-maps ./lib/proc-maps
COPY --chown=user:user ./lib/jail ./lib/jail
COPY --chown=user:user ./lib/asan_symbolize.py ./lib/asan_symbolize.py

COPY --chown=user:user Cargo.lock Cargo.lock
COPY --chown=user:user Cargo.toml Cargo.toml
COPY --chown=user:user ./generator ./generator
COPY --chown=user:user ./consumer ./consumer
COPY --chown=user:user ./scheduler ./scheduler
COPY --chown=user:user ./fuzztruction_shared ./fuzztruction_shared

RUN mkdir -p fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked
RUN mkdir -p fuzztruction-experiments/comparison-with-state-of-the-art/configurations/networked
COPY --chown=user:user fuzztruction-experiments/comparison-with-state-of-the-art/eval fuzztruction-experiments/comparison-with-state-of-the-art/eval
COPY --chown=user:user fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked
COPY --chown=user:user fuzztruction-experiments/comparison-with-state-of-the-art/configurations/networked fuzztruction-experiments/comparison-with-state-of-the-art/configurations/networked

COPY --chown=user:user ./networked-binaries ./networked-binaries
COPY --chown=user:user ./eval ./eval

RUN cargo build --workspace --release
