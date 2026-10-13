cask "chaiwithcode-loom" do
  version "0.1.0"
  sha256 "5ac01b3e1bf673d25fd433c314a4365dcb4efea9f18d1257b632017ddf677595"

  url "https://github.com/chaiwithcode/Loom/releases/download/v#{version}/Loom-#{version}-macOS.zip"
  name "Loom"
  desc "Monitor for local AI coding agents"
  homepage "https://github.com/chaiwithcode/Loom"

  auto_updates true
  depends_on macos: :sonoma

  app "Loom.app"

  zap trash: [
    "~/Library/Application Support/com.chaiwithcode.loom",
    "~/Library/Caches/com.chaiwithcode.loom",
    "~/Library/HTTPStorages/com.chaiwithcode.loom",
    "~/Library/Preferences/com.chaiwithcode.loom.plist",
    "~/Library/Saved Application State/com.chaiwithcode.loom.savedState",
  ]
end
