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

# Install Helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

# Install actionlint (GitHub Actions workflow linter)
RUN curl -fsSL -o /tmp/dl-actionlint.sh https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash \
  && bash /tmp/dl-actionlint.sh latest /usr/local/bin \
  && rm /tmp/dl-actionlint.sh

# Install uv system-wide and create a shared virtualenv under /opt
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_UNMANAGED_INSTALL=1 sh \
  && uv venv /opt/venv \
  && chown -R ubuntu:ubuntu /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Install Rust system-wide via rustup
ENV RUSTUP_HOME=/opt/rust/rustup \
  CARGO_HOME=/opt/rust/cargo
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable \
  && chmod -R a+rwX /opt/rust
ENV PATH="/opt/rust/cargo/bin:${PATH}"

# Skills live at /opt/claude/skills so they survive the ~/.claude volume mount.
# entrypoint.sh symlinks ~/.claude/skills -> /opt/claude/skills at runtime.
RUN mkdir -p /opt/claude/skills /home/ubuntu/.claude \
  && chown -R ubuntu:ubuntu /opt/claude /home/ubuntu/.claude

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Switch to the built-in 'ubuntu' user (UID 1000)
USER ubuntu

# Install skills directly into /opt/claude/skills (baked into the image).
COPY --chown=ubuntu:ubuntu skills.py skills.in.yaml skills.yaml /tmp/skills/
COPY --chown=ubuntu:ubuntu local-skills /tmp/skills/local-skills
RUN cd /tmp/skills \
  && uv run --with pyyaml python skills.py clone \
  && uv run --with pyyaml python skills.py install-skills --target /opt/claude/skills \
  && rm -rf /tmp/skills
