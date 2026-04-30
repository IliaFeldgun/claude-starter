FROM ubuntu:24.04

# Install prerequisites
COPY apt-packages.list /tmp/apt-packages.list
RUN apt-get update \
    && xargs -a /tmp/apt-packages.list apt-get install -y \
    && rm -rf /var/lib/apt/lists/* /tmp/apt-packages.list

# Install Node.js via n (node version manager)
RUN curl -fsSL https://raw.githubusercontent.com/tj/n/master/bin/n -o /usr/local/bin/n \
    && chmod +x /usr/local/bin/n \
    && n lts

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Install uv system-wide and create a shared virtualenv under /opt
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_UNMANAGED_INSTALL=1 sh \
    && uv venv /opt/venv \
    && chown -R ubuntu:ubuntu /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Switch to the built-in 'ubuntu' user (UID 1000)
USER ubuntu

# Pre-create the config directory so the Docker volume inherits correct ownership
RUN mkdir -p /home/ubuntu/.claude
