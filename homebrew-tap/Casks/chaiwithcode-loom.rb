cask "chaiwithcode-loom" do
  version "1.0"
  sha256 "01af2015b9251b9524cbef52dccc3894e2214c462fda2771e7ba7a00a57e2f85"

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
