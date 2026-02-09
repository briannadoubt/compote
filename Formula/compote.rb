class Compote < Formula
  desc "Docker Compose-like tool using Apple's Containerization framework"
  homepage "https://github.com/briannadoubt/compote"
  url "https://github.com/briannadoubt/compote/archive/refs/tags/0.3.0.tar.gz"
  sha256 "e1762ec0cf30ea041dde3f6a1a5b79e166705aa54ef83035f16657f6eb6e0137"
  license "Apache-2.0"
  head "https://github.com/briannadoubt/compote.git", branch: "main"

  bottle do
    root_url "https://github.com/briannadoubt/compote/releases/download/0.3.0"
    sha256 arm64_tahoe: "b4a102c2069bc4b6b269bb635e560cba87fd3f7192035897687f0bb8e19aafa0"
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
