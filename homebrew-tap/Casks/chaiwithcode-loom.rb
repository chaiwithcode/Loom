cask "chaiwithcode-loom" do
  version "0.1.1"
  sha256 "10c08d5e2667ff1dd4742120414247ade6a4ce8a0ff257be79be9b7fa5e259c1"

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
