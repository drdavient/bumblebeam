# Use the openSUSE Leap image
FROM opensuse/leap

# Set environment variable to include /usr/local/bin
ENV PATH="/usr/local/bin:${PATH}"

# Refresh zypper and install the dependencies
RUN zypper --non-interactive refresh && \
    zypper --non-interactive install -y \
        gcc-ada \
        make \
        git \
        libpcap-devel \
        curl \
        unzip \
        ldd \
        file && \
    zypper clean --all

# Set the entrypoint to start a bash shell
ENTRYPOINT ["/bin/bash"]
