# Formula for agent-ear — agentic voice capture & transcription.
#
# This formula installs both binaries:
#   - agent-ear       (Bash TUI shell — interactive wizard powered by gum)
#   - agent-ear-core  (Python engine — the pipeline that agents and scripts call)
#
# Architecture:
#   The Python wheel is installed into a virtualenv in libexec/.
#   pip creates an entry point named "agent-ear" which we rename to "agent-ear-core".
#   The Bash dispatcher script is installed as "agent-ear" and routes to agent-ear-core.
#   Prompt templates are installed to share/agent-ear-templates/.
#
# Native dependencies (portaudio, libsndfile, ffmpeg, gum) are declared via
# depends_on and installed by Homebrew automatically.
#
# Python dependencies are installed via pip from PyPI (not resource blocks)
# because several transitive deps (cryptography, pydantic-core) require
# Rust/maturin to build from source, which is incompatible with Homebrew's
# --no-binary=:all: resource installation policy.

class AgentEar < Formula
  include Language::Python::Virtualenv

  desc "Agentic voice capture — agent-steerable audio transcription"
  homepage "https://github.com/Aurelian-Shuttleworth/agent-ear"
  url "https://github.com/Aurelian-Shuttleworth/agent-ear/archive/refs/tags/v1.1.0-alpha.tar.gz"
  sha256 "5633b7c51784aa073ca1706b4a1a1d0c6dd9204f09648658e56ffeb06e80cb7e"
  license all_of: ["MIT", "Apache-2.0"]

  depends_on "python@3.13"
  depends_on "gum"
  depends_on "portaudio"
  depends_on "libsndfile"
  depends_on "ffmpeg"
  depends_on "yt-dlp" => :recommended

  def install
    # 1. Install Python backend into an isolated virtualenv.
    #    Use pip directly (not Homebrew's resource system) because several
    #    transitive deps (cryptography, pydantic-core) need Rust/maturin
    #    to build from source, which is incompatible with Homebrew's
    #    --no-binary=:all: policy.  pip install with default settings uses
    #    pre-built wheels from PyPI, avoiding the Rust build entirely.
    venv = virtualenv_create(libexec, "python3.13")
    # Install agent-ear + all Python deps from PyPI into the venv.
    # Use python3.13 -m pip (not venv pip) since Homebrew creates venvs
    # with --without-pip. The --python flag targets the venv.
    system "python3.13", "-m", "pip",
           "--python=#{libexec/"bin/python"}",
           "install", "--no-compile", buildpath/"src"

    # pip creates bin/agent-ear (from [project.scripts] in pyproject.toml).
    # Rename to agent-ear-core to match the dual-binary architecture.
    mv bin/"agent-ear", bin/"agent-ear-core"

    # 2. Install prompt templates
    (share/"agent-ear-templates").install Dir["templates/*.md"]
    (share/"agent-ear-templates/internal").install Dir["templates/internal/*.md"]

    # 3. Install the Bash TUI dispatcher with environment wiring.
    #    The script reads AGENT_EAR_TEMPLATES_DIR to find templates and
    #    calls agent-ear-core (which is now on PATH via bin/).
    (bin/"agent-ear").write_env_script(
      libexec/"bin/agent-ear-dispatcher",
      AGENT_EAR_TEMPLATES_DIR: share/"agent-ear-templates",
    )
    cp "scripts/agent-ear.sh", libexec/"bin/agent-ear-dispatcher"
    chmod 0755, libexec/"bin/agent-ear-dispatcher"
  end

  def caveats
    <<~EOS
      agent-ear requires a Google Gemini API key or Vertex AI credentials.

      Quickest setup (Google AI Studio — free tier):
        1. Visit https://aistudio.google.com/apikey
        2. Create an API key
        3. export GOOGLE_API_KEY="your-key-here"

      Full documentation: https://github.com/Aurelian-Shuttleworth/agent-ear
    EOS
  end

  test do
    # Verify the Python engine starts
    assert_match "agent-ear", shell_output("#{bin}/agent-ear-core --help")
    # Verify the dispatcher detects non-TTY and routes to core
    assert_match "agent-ear", shell_output("#{bin}/agent-ear --help")
  end
end
