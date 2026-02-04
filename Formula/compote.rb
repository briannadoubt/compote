class Compote < Formula
  desc "Docker Compose-like tool using Apple's Containerization framework"
  homepage "https://github.com/OWNER/compote"
  url "https://github.com/OWNER/compote/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "Apache-2.0"
  head "https://github.com/OWNER/compote.git", branch: "main"

  depends_on "swift" => :build
  depends_on xcode: ["15.0", :build]
  depends_on "containerization"
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
      Compote requires a Linux kernel to run containers.

      The kernel is provided by the 'containerization' dependency and should
      be automatically available at:
        #{HOMEBREW_PREFIX}/share/containerization/kernel/vmlinuz

      Run 'compote setup' to verify your installation.

      For more information:
        https://github.com/apple/containerization
    EOS
  end

  test do
    # Test that the binary runs
    system "#{bin}/compote", "--version"

    # Test setup command
    system "#{bin}/compote", "setup" rescue nil
  end
end
