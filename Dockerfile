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

# Switch to the built-in 'ubuntu' user (UID 1000)
USER ubuntu

# Pre-create the config directory so the Docker volume inherits correct ownership
RUN mkdir -p /home/ubuntu/.claude
