class Compote < Formula
  desc "Docker Compose-like tool using Apple's Containerization framework"
  homepage "https://github.com/briannadoubt/compote"
  url "https://github.com/briannadoubt/compote/archive/refs/tags/v1.0.1-rc.0-signing-test-20260208-084147.tar.gz"
  sha256 "7c43e9e0c08bf72b9bce6b3458040e3f7ec95356d770d678411af7882668c523"
  license "Apache-2.0"
  head "https://github.com/briannadoubt/compote.git", branch: "main"

  bottle do
    root_url "https://github.com/briannadoubt/compote/releases/download/v1.0.1-rc.0-signing-test-20260208-084147"
    sha256 arm64_tahoe: "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"
  end
  
  depends_on "swift" => :build
  depends_on xcode: ["16.0", :build]
  depends_on macos: :sequoia
  depends_on "socat"

  def install
    system "swift", "build",
           "--disable-sandbox",
           "-c", "release",
           "--product", "compote"
    bin.install ".build/release/compote"

    # Install shell completions (optional)
    generate_completions_from_executable(bin/"compote", "--generate-completion-script")
  end

  def caveats
    <<~EOS
      Compote uses Apple's Containerization framework to run Linux containers on macOS.

      Requirements:
        - macOS Sequoia (15.0) or later
        - Xcode 16.0 or later
        - Linux kernel (automatically downloaded on first run)

      Run 'compote setup' to verify your installation and download required components.
      Note: TCP/UDP port forwarding via service ports requires socat (installed as a formula dependency).

      For more information:
        https://github.com/briannadoubt/compote
    EOS
  end

  test do
    # Test that the binary runs
    system bin/"compote", "--version"

    # Setup may be unavailable in sandboxed CI contexts.
    begin
      system bin/"compote", "setup"
    rescue RuntimeError
      nil
    end
  end
end
