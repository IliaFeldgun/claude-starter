FROM ubuntu:24.04

# Install prerequisites
COPY apt-packages.list /tmp/apt-packages.list
RUN apt-get update \
  && xargs -a /tmp/apt-packages.list apt-get install -y \
  && ln -sf /usr/bin/batcat /usr/local/bin/bat \
  && rm -rf /var/lib/apt/lists/* /tmp/apt-packages.list

# Install Rust system-wide via rustup. Placed early: it's the longest build step
# and changes least often, so it stays cached when later layers churn.
ENV RUSTUP_HOME=/opt/rust/rustup \
  CARGO_HOME=/opt/rust/cargo
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable \
  && chmod -R a+rwX /opt/rust
ENV PATH="/opt/rust/cargo/bin:${PATH}"

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

# Install Neovim (official release, multi-arch)
RUN ARCH=$(dpkg --print-architecture) \
  && case "$ARCH" in \
       amd64) NVIM_ARCH=x86_64 ;; \
       arm64) NVIM_ARCH=arm64 ;; \
       *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;; \
     esac \
  && curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz" -o /tmp/nvim.tar.gz \
  && tar -xzf /tmp/nvim.tar.gz -C /opt \
  && mv "/opt/nvim-linux-${NVIM_ARCH}" /opt/nvim \
  && rm /tmp/nvim.tar.gz

# Wrap nvim so Mason resolves the uv-backed python shim ahead of the real
# interpreter (without polluting the global PATH); see nvim/nvim-mason-uv-shim.sh.
COPY nvim/nvim-mason-uv-shim.sh /opt/nvim-shim/nvim-mason-uv-shim.sh
RUN mkdir -p /opt/nvim-shim/bin \
  && chmod +x /opt/nvim-shim/nvim-mason-uv-shim.sh \
  && for p in python3 python python3.12; do \
       ln -s /opt/nvim-shim/nvim-mason-uv-shim.sh "/opt/nvim-shim/bin/$p"; \
     done \
  && printf '#!/usr/bin/env bash\nexport PATH="/opt/nvim-shim/bin:$PATH"\nexec /opt/nvim/bin/nvim --cmd "luafile /opt/nvim-global/clipboard.lua" "$@"\n' > /usr/local/bin/nvim \
  && chmod +x /usr/local/bin/nvim

# Register the OSC 52 clipboard provider globally: the nvim wrapper sources this
# via --cmd before any config loads, so it applies whether the user runs the
# staged starter or bind-mounts their own (read-only) ~/.config/nvim. A
# runtimepath plugin would not survive lazy.nvim's rtp reset; --cmd does.
COPY nvim/nvim-clipboard.lua /opt/nvim-global/clipboard.lua

# Stage LazyVim starter; entrypoint seeds ~/.config/nvim from this.
RUN git clone --depth 1 https://github.com/LazyVim/starter /opt/nvim-starter \
  && rm -rf /opt/nvim-starter/.git \
  && chown -R ubuntu:ubuntu /opt/nvim-starter

# Install GitHub CLI (gh)
RUN ARCH=$(dpkg --print-architecture) \
  && GH_VERSION=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | jq -r .tag_name | sed 's/^v//') \
  && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" -o /tmp/gh.tar.gz \
  && tar -xzf /tmp/gh.tar.gz -C /tmp \
  && mv "/tmp/gh_${GH_VERSION}_linux_${ARCH}/bin/gh" /usr/local/bin/gh \
  && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_${ARCH}"

# Install kubectl (official release, multi-arch)
RUN ARCH=$(dpkg --print-architecture) \
  && KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt) \
  && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" -o /usr/local/bin/kubectl \
  && chmod 755 /usr/local/bin/kubectl

# Install Datadog MCP CLI (single static binary, multi-arch)
RUN ARCH=$(dpkg --print-architecture) \
  && curl -fsSL "https://coterm.datadoghq.com/mcp-cli/datadog_mcp_cli-linux-${ARCH}" -o /usr/local/bin/datadog_mcp_cli \
  && chmod 755 /usr/local/bin/datadog_mcp_cli

# Install uv system-wide and create a shared virtualenv under /opt.
# /opt/uv-envs is a writable home for per-project ephemeral venvs (see uv skill).
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_UNMANAGED_INSTALL=1 sh \
  && uv venv /opt/venv \
  && mkdir -p /opt/uv-envs \
  && chown -R ubuntu:ubuntu /opt/venv /opt/uv-envs
ENV PATH="/opt/venv/bin:${PATH}"

# Install Go (official release, multi-arch) so Mason can build its Go tools
# (gopls, gofumpt, goimports) — they fail without `go` in PATH.
RUN ARCH=$(dpkg --print-architecture) \
  && GO_VERSION=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -n1) \
  && curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz \
  && tar -C /usr/local -xzf /tmp/go.tar.gz \
  && rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# Skills live at /opt/claude/skills so they survive the ~/.claude volume mount.
# entrypoint.sh symlinks ~/.claude/skills -> /opt/claude/skills at runtime.
RUN mkdir -p /opt/claude/skills /opt/claude/bin /home/ubuntu/.claude \
  && chown -R ubuntu:ubuntu /opt/claude /home/ubuntu/.claude

# Statusbar renderer + record/clear hooks; wired into ~/.claude/settings.json by
# entrypoint.sh. All share the statusbar- prefix so the merge can prune/re-add them.
COPY statusbar/ /opt/claude/bin/
RUN chmod +x /opt/claude/bin/statusbar.sh /opt/claude/bin/statusbar-skill.sh /opt/claude/bin/statusbar-mcp.sh /opt/claude/bin/statusbar-clear.sh /opt/claude/bin/statusbar-pr.sh

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
