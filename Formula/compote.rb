class Compote < Formula
  desc "Docker Compose-like tool using Apple's Containerization framework"
  homepage "https://github.com/briannadoubt/compote"
  url "https://github.com/briannadoubt/compote/archive/refs/tags/v1.0.1-rc.0-test3-20260208.tar.gz"
  sha256 "ba815073ee31ca75886d48ca0d575ad9ae0147fd63dce06b8bf5bf6237e2e4dd"
  license "Apache-2.0"
  head "https://github.com/briannadoubt/compote.git", branch: "main"

  bottle do
    root_url "https://github.com/briannadoubt/compote/releases/download/v1.0.1-rc.0-test3-20260208"
    sha256 arm64_tahoe: "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"
  end
  
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
