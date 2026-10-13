cask "chaiwithcode-loom" do
  version "0.1.0"
  sha256 "d467fbfe2b7d1be651728f9d86f041e3f76688b7136ec465ed5633c5e75b7aa5"

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
