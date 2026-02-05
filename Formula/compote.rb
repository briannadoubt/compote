class Compote < Formula
  desc "Docker Compose-like tool using Apple's Containerization framework"
  homepage "https://github.com/briannadoubt/compote"
  url "https://github.com/briannadoubt/compote/archive/refs/tags/0.2.0.tar.gz"
  sha256 "b7944727dd8f7321e4c1f22a893e7e88f43d2e00ff45ec4ff727a51e5468bd2b"
  license "Apache-2.0"
  head "https://github.com/briannadoubt/compote.git", branch: "main"

  depends_on "swift" => :build
  depends_on xcode: ["16.0", :build]
  depends_on :macos => :sequoia

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

      For more information:
        https://github.com/briannadoubt/compote
    EOS
  end

  test do
    # Test that the binary runs
    system "#{bin}/compote", "--version"

    # Test setup command
    system "#{bin}/compote", "setup" rescue nil
  end
end
